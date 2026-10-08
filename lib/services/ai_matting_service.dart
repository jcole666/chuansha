import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'matte_blend.dart';

/// 一个抠图模型的规格（预处理参数 + 资源路径）。
class _ModelSpec {
  /// ONNX 资源路径
  final String asset;

  /// 展示名（日志/提示用）
  final String label;

  /// 正方形输入边长（模型固定输入）
  final int inputSize;

  /// 标准化参数：v_norm = (v/255 - mean) / std
  final double mean;
  final double std;

  const _ModelSpec({
    required this.asset,
    required this.label,
    required this.inputSize,
    required this.mean,
    required this.std,
  });
}

/// AI 抠图服务：用 ONNX 分割模型做主体分割，把背景填成白色。
///
/// 与 [MattingService]（纯颜色洪水填充，只吃纯色背景）的区别：
/// 这是**神经网络分割模型**，能真正理解「主体 vs 背景」。
///
/// 采用**两级模型**，按顺序尝试，第一个成功的即返回：
///
/// 1. `assets/models/rmbg14_fp16.onnx` —— BRIA **RMBG-1.4**（84MB，fp16）
///    通用背景去除，质量明显更好。实测（米白大衣 + 白背景这种低对比度难题）
///    灰边占比 0.3%，而 MODNet 是 3.8%；水印/杂物也能清掉。
///    ⚠️ 输入固定 1024x1024，手机上推理较慢（数秒级）。
///    输入 `input` [1,3,1024,1024] float；输出 `output` [1,1,H,W]，已是
///    sigmoid 后的 [0,1] alpha。标准化：mean=0.5, std=1.0（即 v/255-0.5）。
///    ⚠️ **许可**：bria-rmbg-1.4 = CC BY-NC 4.0，**仅限非商业用途**。
///    本项目为个人自用，符合；若将来商用需换成可商用模型。
///
/// 2. `assets/models/modnet_fp16.onnx` —— **MODNet**（12MB，fp16，Apache-2.0）
///    兜底。它本质是**人像**抠图模型（Real-Time Trimap-Free Portrait
///    Matting），对单件衣服 + 干净背景够用，低对比度会吃力；但只有 12MB
///    且 512 输入很快，作为 RMBG 不可用时的保险。
///    输入 `input` [1,3,H,W] float；输出 `output` [1,1,H,W] [0,1]。
///    标准化：mean=0.5, std=0.5（即 v/255*2-1）。
///
/// 两者的共同点：输入都是**压成正方形**（不保持长宽比）——
/// MODNet 官方就是压成正方形训练/推理的，实测比"保持比例"更干净，
/// 而且像素更少、更快。
///
/// 后处理：alpha 双线性放大回原图 → **锐化（压灰边）** → 轻度羽化 →
///   与白色按 alpha 混合（[compositeOnWhiteWithAlpha]）。
class AiMattingService {
  AiMattingService._();

  static final AiMattingService instance = AiMattingService._();

  /// 模型列表，按优先级从高到低。
  static const List<_ModelSpec> _specs = [
    _ModelSpec(
      asset: 'assets/models/rmbg14_fp16.onnx',
      label: 'RMBG-1.4',
      inputSize: 1024,
      mean: 0.5,
      std: 1.0,
    ),
    _ModelSpec(
      asset: 'assets/models/modnet_fp16.onnx',
      label: 'MODNet',
      inputSize: 512,
      mean: 0.5,
      std: 0.5,
    ),
  ];

  /// alpha 锐化强度：把模型输出的灰边往 0/1 推。
  /// 1.0 = 不处理。实测 1.8 能把低对比度场景的灰区占比明显降下来，
  /// 而真实前景/背景几乎不受影响。
  static const double _alphaSharpen = 1.8;

  final Map<String, OrtSession> _sessions = {};
  final Map<String, OrtSessionOptions> _options = {};
  bool _envInited = false;

  /// 最近一次失败的原始原因（UI 可用来显示更精确的提示）
  String? lastError;

  /// 实际生效的模型名（抠图成功后可用）
  String? lastUsedModel;

  /// 模型是否已就绪（探针：不抛异常，给 UI 判断用）
  ///
  /// 只要**任意一个**模型能加载就返回 true（优先 RMBG）。
  Future<bool> isAvailable() async {
    for (final spec in _specs) {
      try {
        await _ensureSession(spec);
        return true;
      } catch (e) {
        lastError = '${spec.label}: $e';
      }
    }
    return false;
  }

  Future<OrtSession> _ensureSession(_ModelSpec spec) async {
    final cached = _sessions[spec.asset];
    if (cached != null) return cached;

    if (!_envInited) {
      OrtEnv.instance.init();
      _envInited = true;
    }

    // 关键：线程数必须在创建 session **之前**设置 ——
    // OrtSessionOptions 是在 fromBuffer() 里被消费的，之后再改不生效。
    final opts = OrtSessionOptions();
    opts.setInterOpNumThreads(1);
    opts.setIntraOpNumThreads(2);

    final raw = await rootBundle.load(spec.asset);
    final bytes = raw.buffer.asUint8List();
    final session = OrtSession.fromBuffer(bytes, opts);

    _options[spec.asset] = opts;
    _sessions[spec.asset] = session;
    return session;
  }

  /// 对图片执行 AI 抠图，返回白底 PNG 文件。
  ///
  /// 依次尝试各模型，第一个成功的即返回。
  /// 全部失败时抛 [AiMattingException]（带人话 message）。
  Future<File> removeBackground(File imageFile) async {
    final original = img.decodeImage(await imageFile.readAsBytes());
    if (original == null) {
      throw const AiMattingException('无法解析图片，请换一张试试');
    }

    final errors = <String>[];
    for (final spec in _specs) {
      try {
        final alpha = await _runModel(spec, original);
        lastUsedModel = spec.label;
        return _writeWhiteBackground(imageFile, original, alpha);
      } catch (e) {
        errors.add('${spec.label}: $e');
        lastError = errors.last;
      }
    }
    throw AiMattingException('抠图模型不可用（${errors.join('; ')}）');
  }

  /// 跑单个模型，返回**原图尺寸**的 alpha（0..1，已锐化+羽化）。
  Future<Float32List> _runModel(_ModelSpec spec, img.Image original) async {
    final session = await _ensureSession(spec);

    // 1) 预处理：压成正方形
    final size = spec.inputSize;
    final pre = img.copyResize(
      original,
      width: size,
      height: size,
      interpolation: img.Interpolation.linear,
    );

    // 2) 组装 NCHW float32 输入
    final plane = size * size;
    final inputData = Float32List(3 * plane);
    final rgba = pre.getBytes(order: img.ChannelOrder.rgba);
    for (var y = 0; y < size; y++) {
      final rowBase = y * size;
      for (var x = 0; x < size; x++) {
        final p = (rowBase + x) * 4;
        final idx = rowBase + x;
        // 标准化：(v/255 - mean) / std
        inputData[idx] =
            (rgba[p] / 255.0 - spec.mean) / spec.std;
        inputData[plane + idx] =
            (rgba[p + 1] / 255.0 - spec.mean) / spec.std;
        inputData[plane * 2 + idx] =
            (rgba[p + 2] / 255.0 - spec.mean) / spec.std;
      }
    }

    // 3) 推理
    final inputOrt = OrtValueTensor.createTensorWithDataList(inputData, [
      1,
      3,
      size,
      size,
    ]);
    final inputs = <String, OrtValue>{'input': inputOrt};
    final runOptions = OrtRunOptions();

    List<OrtValue?>? outputs;
    try {
      // runAsync 签名返回可空的 Future（首次调用才初始化 isolate），
      // 这里显式判空，避免 null 解引用。
      final future = session.runAsync(runOptions, inputs);
      if (future == null) {
        throw const AiMattingException('抠图模型未能启动推理');
      }
      outputs = await future;
    } catch (e) {
      if (e is AiMattingException) rethrow;
      throw AiMattingException('推理失败：$e');
    } finally {
      inputOrt.release();
      runOptions.release();
    }

    if (outputs.isEmpty || outputs.first == null) {
      throw const AiMattingException('模型没有返回结果');
    }

    // 4) 取出 [1,1,H,W] 的 alpha，压平成一维
    final outValue = outputs.first!;
    final alpha = _flattenAlpha(outValue.value, plane);
    outValue.release();

    // 5) 放大回原图尺寸
    final origW = original.width;
    final origH = original.height;
    final fullAlpha = _resizeAlpha(alpha, size, size, origW, origH);

    // 6) 锐化：压掉低对比度场景下模型输出的灰边
    _sharpenAlpha(fullAlpha, _alphaSharpen);

    // 7) 轻度羽化，抹掉模型输出的板块边缘
    _featherAlpha(fullAlpha, origW, origH, 1);

    return fullAlpha;
  }

  /// 把 alpha 合成到白底并写成 PNG 文件。
  File _writeWhiteBackground(
    File imageFile,
    img.Image original,
    Float32List fullAlpha,
  ) {
    final origW = original.width;
    final origH = original.height;
    final srcBytes = original.getBytes(order: img.ChannelOrder.rgba);
    final outBytes = compositeOnWhiteWithAlpha(
      srcBytes,
      origW,
      origH,
      fullAlpha,
    );

    final outDir = imageFile.parent;
    final outPath =
        '${outDir.path}${Platform.pathSeparator}ai_matte_${DateTime.now().millisecondsSinceEpoch}.png';
    File(outPath).writeAsBytesSync(
      img.encodePng(
        img.Image.fromBytes(
          width: origW,
          height: origH,
          bytes: outBytes.buffer,
          numChannels: 4,
        ),
      ),
    );
    return File(outPath);
  }

  /// 释放模型与运行环境（页面销毁 / App 退出时调用）
  void dispose() {
    for (final s in _sessions.values) {
      s.release();
    }
    for (final o in _options.values) {
      o.release();
    }
    _sessions.clear();
    _options.clear();
    if (_envInited) {
      OrtEnv.instance.release();
      _envInited = false;
    }
  }

  /// 把模型输出（可能是嵌套 List 或 typed list）压平成长度 [expected] 的 alpha。
  ///
  /// `OrtValueTensor.value` 对 [1,1,H,W] 返回的是四层嵌套的
  /// `List<List<List<List<double>>>>>`，所以这里用递归 walk 而不是直接类型断言。
  Float32List _flattenAlpha(Object? outData, int expected) {
    final result = Float32List(expected);
    var i = 0;

    void walk(Object? node) {
      if (i >= result.length) return;
      if (node is num) {
        result[i++] = node.toDouble();
        return;
      }
      if (node is List) {
        for (final e in node) {
          walk(e);
          if (i >= result.length) return;
        }
        return;
      }
      if (node is Float32List ||
          node is Float64List ||
          node is Int32List ||
          node is Int64List ||
          node is Uint8List) {
        // 必须先升成 Iterable<num>：Dart 对 typed list 的联合类型
        // 不做隐式逐元素迭代（编译器无法从任一分支推出 element 类型）。
        final typed = node as Iterable<num>;
        for (final v in typed) {
          if (i >= result.length) return;
          result[i++] = v.toDouble();
        }
        return;
      }
    }

    walk(outData);
    // 兜底：模型输出数量不足时，剩余像素按全前景处理（宁可保留多一点）
    for (; i < result.length; i++) {
      result[i] = 1.0;
    }
    return result;
  }

  /// 双线性放大 alpha 到目标尺寸。
  Float32List _resizeAlpha(Float32List src, int sw, int sh, int dw, int dh) {
    final out = Float32List(dw * dh);
    if (sw == dw && sh == dh) {
      out.setAll(0, src);
      return out;
    }
    final xRatio = (sw - 1) / (dw - 1 <= 0 ? 1 : dw - 1);
    final yRatio = (sh - 1) / (dh - 1 <= 0 ? 1 : dh - 1);
    for (var y = 0; y < dh; y++) {
      final sy = y * yRatio;
      final y0 = sy.floor();
      final y1 = math.min(y0 + 1, sh - 1);
      final wy = sy - y0;
      for (var x = 0; x < dw; x++) {
        final sx = x * xRatio;
        final x0 = sx.floor();
        final x1 = math.min(x0 + 1, sw - 1);
        final wx = sx - x0;
        final a = src[y0 * sw + x0];
        final b = src[y0 * sw + x1];
        final c = src[y1 * sw + x0];
        final d = src[y1 * sw + x1];
        final top = a + (b - a) * wx;
        final bot = c + (d - c) * wx;
        out[y * dw + x] = top + (bot - top) * wy;
      }
    }
    return out;
  }

  /// 把 alpha 往 0/1 推，压掉模型输出的"灰边"。
  ///
  /// 低对比度场景（白衣服 + 白背景）模型会输出大片 0.2~0.8 的灰值，
  /// 合成到白底后看起来就是"背景没抠干净 / 衣服边缘发糊"。
  /// 用一个绕 0.5 的线性拉伸即可显著改善，且不影响明确的前景/背景。
  void _sharpenAlpha(Float32List a, double k) {
    if (k <= 1.0) return;
    for (var i = 0; i < a.length; i++) {
      final v = (a[i] - 0.5) * k + 0.5;
      a[i] = v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
    }
  }

  /// 对 alpha 做 [rounds] 轮 3x3 均值模糊，柔化边缘。
  void _featherAlpha(Float32List a, int w, int h, int rounds) {
    if (rounds <= 0) return;
    var cur = a;
    for (var r = 0; r < rounds; r++) {
      final next = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var sum = 0.0;
          var cnt = 0;
          for (var dy = -1; dy <= 1; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= h) continue;
            for (var dx = -1; dx <= 1; dx++) {
              final xx = x + dx;
              if (xx < 0 || xx >= w) continue;
              sum += cur[yy * w + xx];
              cnt++;
            }
          }
          next[y * w + x] = cnt == 0 ? cur[y * w + x] : sum / cnt;
        }
      }
      cur = next;
    }
    a.setAll(0, cur);
  }
}

/// AI 抠图异常（用户可理解的错误，页面直接展示 message）
class AiMattingException implements Exception {
  final String message;
  const AiMattingException(this.message);

  @override
  String toString() => message;
}
