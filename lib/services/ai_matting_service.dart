import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'matte_blend.dart';

/// AI 抠图服务：用 MODNet（ONNX）做主体分割，把背景填成白色。
///
/// 与 [MattingService]（纯颜色洪水填充，只吃纯色背景）的区别：
/// 这是一个**神经网络分割模型**，能真正理解「主体 vs 背景」——
/// 花地板、衣服堆一起、浅色衣服都能抠，效果接近醒图/美图秀秀的智能抠图。
///
/// 模型信息（`assets/models/modnet_fp16.onnx`，Apache-2.0，来自
/// `Xenova/modnet` 的 fp16 导出，约 12MB）：
///   - 输入 `input`  : float32, NCHW [1, 3, H, W]，值域 [-1, 1]
///   - 输出 `output` : float32, NCHW [1, 1, H, W]，值域 [0, 1]（alpha）
///   - H/W 必须是 32 的倍数（模型对下采样有 32 的约数要求）
///
/// 预处理（对齐 transformers.js 的 ImageFeatureExtractor）：
///   resize（短边 512，保持比例、向上取到 32 的倍数）→ 归一化到 [0,1]
///   → 按 mean=std=0.5 标准化 → [-1, 1]
///
/// 后处理：把 0..1 的 alpha 双线性放大回原图尺寸 → 轻度羽化 →
///   与白色按 alpha 混合（[compositeOnWhiteWithAlpha]）。
///
/// 注意：推理耗时与分辨率相关，512 短边在手机上通常 0.3–1.5 秒；
/// 本服务在调用方 isolate 里跑，不要在 UI 线程直接调用。
class AiMattingService {
  AiMattingService._();

  static final AiMattingService instance = AiMattingService._();

  /// 模型资源路径
  static const String _modelAsset = 'assets/models/modnet_fp16.onnx';

  /// 预处理目标短边（对齐模型训练配置）
  static const int _shortEdge = 512;

  /// 网络下采样倍数约束：宽高必须是它的整数倍
  static const int _sizeDivisibility = 32;

  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _envInited = false;

  /// 最近一次失败的原始原因（UI 可用来显示更精确的提示）
  String? lastError;

  /// 模型是否已就绪（探针：不抛异常，给 UI 判断用）
  Future<bool> isAvailable() async {
    try {
      await _ensureSession();
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<void> _ensureSession() async {
    if (_session != null) return;
    if (!_envInited) {
      OrtEnv.instance.init();
      _envInited = true;
    }

    // 关键：线程数必须在创建 session **之前**设置 ——
    // OrtSessionOptions 是在 fromBuffer() 里被消费的，之后再改不生效。
    final opts = OrtSessionOptions();
    opts.setInterOpNumThreads(1);
    opts.setIntraOpNumThreads(2);

    final raw = await rootBundle.load(_modelAsset);
    final bytes = raw.buffer.asUint8List();
    _sessionOptions = opts;
    _session = OrtSession.fromBuffer(bytes, opts);
  }

  /// 对图片执行 AI 抠图，返回白底 PNG 文件。
  ///
  /// 失败抛 [AiMattingException]（带人话 message）。
  Future<File> removeBackground(File imageFile) async {
    final original = img.decodeImage(await imageFile.readAsBytes());
    if (original == null) {
      throw const AiMattingException('无法解析图片，请换一张试试');
    }

    await _ensureSession();

    // 1) 预处理：等比例缩放到短边 512，并向上对齐到 32 的倍数
    final pre = _preprocess(original);
    final inW = pre.width;
    final inH = pre.height;

    // 2) 组装 NCHW float32 输入，值域 [-1, 1]
    final inputData = Float32List(1 * 3 * inH * inW);
    // 注意：image 包按 RGBA 存，取 RGB 并转 NCHW
    //   通道布局：R 平面、G 平面、B 平面
    final rgba = pre.getBytes(order: img.ChannelOrder.rgba);
    final plane = inW * inH;
    for (var y = 0; y < inH; y++) {
      for (var x = 0; x < inW; x++) {
        final p = (y * inW + x) * 4;
        final r = rgba[p] / 255.0;
        final g = rgba[p + 1] / 255.0;
        final b = rgba[p + 2] / 255.0;
        final idx = y * inW + x;
        // 标准化：(v - 0.5) / 0.5 = v * 2 - 1
        inputData[idx] = r * 2.0 - 1.0;
        inputData[plane + idx] = g * 2.0 - 1.0;
        inputData[plane * 2 + idx] = b * 2.0 - 1.0;
      }
    }

    // 3) 推理
    final shape = [1, 3, inH, inW];
    final inputOrt = OrtValueTensor.createTensorWithDataList(
      inputData,
      shape,
    );
    final inputs = <String, OrtValue>{'input': inputOrt};
    final runOptions = OrtRunOptions();

    List<OrtValue?>? outputs;
    try {
      // runAsync 签名返回可空的 Future（首次调用才初始化 isolate），
      // 这里显式判空，避免 null 解引用。
      final future = _session!.runAsync(runOptions, inputs);
      if (future == null) {
        throw const AiMattingException('抠图模型未能启动推理');
      }
      outputs = await future;
    } catch (e) {
      if (e is AiMattingException) rethrow;
      throw AiMattingException('抠图模型推理失败：$e');
    } finally {
      inputOrt.release();
      runOptions.release();
    }

    if (outputs.isEmpty) {
      throw const AiMattingException('抠图模型没有返回结果');
    }

    // 4) 取出 [1,1,H,W] 的 alpha，压平成一维
    final outValue = outputs.first;
    if (outValue == null) {
      throw const AiMattingException('抠图模型返回了空结果');
    }
    final outData = outValue.value;
    final alpha = _flattenAlpha(outData, inW, inH);
    outValue.release();

    // 5) 把 alpha 放大回原图尺寸
    final origW = original.width;
    final origH = original.height;
    final fullAlpha = _resizeAlpha(alpha, inW, inH, origW, origH);

    // 6) 轻度羽化，抹掉模型输出的板块边缘
    _featherAlpha(fullAlpha, origW, origH, 1);

    // 7) 合并到白底
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
    _session?.release();
    _sessionOptions?.release();
    _session = null;
    _sessionOptions = null;
    if (_envInited) {
      OrtEnv.instance.release();
      _envInited = false;
    }
  }

  /// 等比缩放到短边 [_shortEdge]，宽高向上对齐 [_sizeDivisibility] 的倍数。
  img.Image _preprocess(img.Image src) {
    final w = src.width;
    final h = src.height;
    final scale = _shortEdge / math.min(w, h);
    var tw = (w * scale).round();
    var th = (h * scale).round();
    tw = _roundUpTo(tw, _sizeDivisibility);
    th = _roundUpTo(th, _sizeDivisibility);
    return img.copyResize(
      src,
      width: tw,
      height: th,
      interpolation: img.Interpolation.linear,
    );
  }

  int _roundUpTo(int v, int m) => ((v + m - 1) ~/ m) * m;

  /// 把模型输出（可能是嵌套 List 或 typed list）压平成长度 w*h 的 alpha。
  ///
  /// `OrtValueTensor.value` 对 [1,1,H,W] 返回的是四层嵌套的
  /// `List<List<List<List<double>>>>>`（见 onnxruntime 的 `.reshape<double>`），
  /// 所以这里用递归 walk 而不是直接类型断言。
  Float32List _flattenAlpha(Object? outData, int w, int h) {
    final result = Float32List(w * h);
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
