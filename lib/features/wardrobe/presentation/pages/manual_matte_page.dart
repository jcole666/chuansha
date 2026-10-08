import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../../core/error_log.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/manual_matte_service.dart';
import '../../../../services/matte_geometry.dart';

/// 新版手动抠图页（PS 磁性套索风格 + 右上角放大镜）。
///
/// 交互（对齐 Photoshop 磁性套索的直觉）：
/// 1. 手指沿衣服边缘**点一下** → 落一个锚点（自动吸附到最近边缘）
/// 2. 沿边缘**拖动/滑动** → 自动生成一条吸附边缘的曲线（livewire 最短路）
/// 3. 靠近起点**点一下** → 闭合成选区
/// 4. 已落下的锚点可以**拖动微调**（长按拖动锚点）
/// 5. 右上角常驻**放大镜**：手指在哪就把那块放大显示，不被手指挡住
///
/// 「自动吸附」开关关掉后，退化成自由手绘（和旧版一致）。
///
/// 返回抠好的图片 [File]，取消返回 null。
class ManualMattePage extends StatefulWidget {
  final File imageFile;

  /// 是否默认开启边缘吸附
  final bool initialSnap;

  const ManualMattePage({
    super.key,
    required this.imageFile,
    this.initialSnap = true,
  });

  @override
  State<ManualMattePage> createState() => _ManualMattePageState();
}

class _ManualMattePageState extends State<ManualMattePage> {
  final _polygons = <List<Offset>>[]; // 已完成的多边形（归一化）

  /// 当前这一圈的**统一点列**（归一化，按落点先后顺序）。
  ///
  /// 用一条列表同时装「点出来的锚点」和「拖出来的 livewire 路径」，
  /// 因为它们本来就是**时间上交错**的：用户可能点两下、拖一段、再点一下闭合。
  /// 如果分成两个列表，画笔拼接时会从最后一个锚点直接跳到轮廓起点，
  /// 画面里就多一条莫名其妙的直线。
  final _current = <Offset>[];

  /// 其中被用户**显式点下**的锚点下标（画笔只给这些位置画圆点）
  final _anchorIdx = <int>[];

  bool _snapToEdge = true;
  bool _processing = false;

  // 图像与梯度数据（像素级，供吸附/livewire 用）
  Float32List? _grad;
  Float32List? _edgeDist;
  int _workW = 0;
  int _workH = 0;

  // livewire 当前悬停预览路径（归一化，从当前路径末点到手指位置）
  List<Offset>? _previewPath;
  // 手指当前归一化位置（驱动放大镜）
  Offset? _fingerPos;
  // 上一次真正重算 livewire 时的手指位置（用来做移动阈值节流）
  Offset? _lastLivewireAt;
  // 正在拖动的锚点索引（指 _current 里的下标；-1 = 无）
  int _draggingAnchor = -1;

  Size? _imageSize;
  bool _loading = true;
  String? _loadError;

  /// livewire 在多大的工作分辨率上算（越大越准越慢）
  static const int _workMaxDim = 900;

  /// 参数半径（像素）—— 手指附近多远算"吸附到边缘"
  static const int _snapRadiusPx = 7;

  @override
  void initState() {
    super.initState();
    _snapToEdge = widget.initialSnap;
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      // 显示尺寸
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();

      // 解码用于算法的工作图
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('无法解析图片');
      final scale = decoded.width > _workMaxDim || decoded.height > _workMaxDim
          ? _workMaxDim / math.max(decoded.width, decoded.height)
          : 1.0;
      final working = scale < 1.0
          ? img.copyResize(
              decoded,
              width: (decoded.width * scale).round(),
              height: (decoded.height * scale).round(),
              interpolation: img.Interpolation.linear,
            )
          : decoded;

      final w = working.width;
      final h = working.height;
      final rgba = working.getBytes(order: img.ChannelOrder.rgba);
      final grad = sobelGradient(rgba, w, h);
      // 自适应阈值：用梯度均值的一定倍数，避免不同照片一个阈值走天下
      var sum = 0.0;
      for (final g in grad) {
        sum += g;
      }
      final thr = math.max(30.0, (sum / grad.length) * 2.5);
      final edges = strongEdges(grad, thr);
      final edgeDist = distanceToFeature(edges, w, h, 40);

      if (!mounted) return;
      setState(() {
        _grad = grad;
        _edgeDist = edgeDist;
        _workW = w;
        _workH = h;
        _imageSize = size;
        _loading = false;
      });
    } catch (e, s) {
      ErrorLog.record('手动抠图-加载', e, s);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '图片加载失败，请重试';
      });
    }
  }

  // ---------- 坐标换算 ----------

  Rect _imageRect(Size container) {
    final size = _imageSize ?? const Size(1, 1);
    if (size.width <= 0 || size.height <= 0) return Offset.zero & container;
    final scale = math.min(
      container.width / size.width,
      container.height / size.height,
    );
    final w = size.width * scale;
    final h = size.height * scale;
    return Rect.fromLTWH(
      (container.width - w) / 2,
      (container.height - h) / 2,
      w,
      h,
    );
  }

  Offset _toNormalized(Offset local, Rect rect) {
    if (rect.width <= 0 || rect.height <= 0) return Offset.zero;
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  // ---------- livewire ----------

  /// 从 [from]（归一化）到 [to]（归一化）求吸附路径（归一化点列）。
  List<Offset>? _livewire(Offset from, Offset to) {
    final ed = _edgeDist;
    if (ed == null || !_snapToEdge) return null;
    final sp = MattePoint(from.dx * _workW, from.dy * _workH);
    final gp = MattePoint(to.dx * _workW, to.dy * _workH);
    final path = livewirePath(
      seed: sp,
      goal: gp,
      edgeDist: ed,
      w: _workW,
      h: _workH,
    );
    if (path.length < 2) return null;
    return path
        .map((p) => Offset(p.x / _workW, p.y / _workH))
        .toList(growable: false);
  }

  /// 把触点吸附到附近最强边缘（放大镜/落点用）
  Offset _snapPoint(Offset norm) {
    final grad = _grad;
    if (grad == null || !_snapToEdge) return norm;
    final p = snapPointToEdge(
      MattePoint(norm.dx * _workW, norm.dy * _workH),
      grad,
      _workW,
      _workH,
      _snapRadiusPx,
      60.0,
    );
    return Offset(p.x / _workW, p.y / _workH);
  }

  // ---------- 手势 ----------
  //
  // 交互模型（对齐 PS 磁性套索）：
  //   - **点击（tap）**    → 在当前路径末尾落一个锚点（吸附到边缘）
  //   - **拖动（pan）**    → livewire 预览，松手时把整条路径追加进当前路径
  //   - **点已落锚点**      → 拖动微调
  //   - **点回起点**        → 闭合
  //
  // 关键：Flutter 在同一次拖动里会**先**触发 onTapDown、再触发 onPanStart，
  // 如果两处都落点，一次拖动就会落两个锚点（而且一个吸附过、一个没有）。
  // 所以 tap 只"预记"意图（`_pendingAnchor` / `_pendingClose`），
  // 到 onPanStart 里作废、到 onTapUp 里才真正生效。

  /// tap 预记的落点（归一化）；pan 一旦开始就作废
  Offset? _pendingAnchor;

  /// tap 预记的"闭合"意图；pan 一旦开始就作废
  bool _pendingClose = false;

  void _onTapDown(TapDownDetails d, Rect rect) {
    final norm = _toNormalized(d.localPosition, rect);

    // 先判断有没有点到已有锚点（锚点编辑优先级最高）
    final hit = _hitAnchor(norm, rect);
    if (hit >= 0) {
      setState(() => _draggingAnchor = hit);
      return;
    }

    // 点到起点附近 → 预记"闭合"
    // 同时覆盖「点出来的锚点」和「拖出来的轮廓」——否则纯靠拖描一圈的人
    // 回到起点点一下会没反应。
    if (_current.length >= 3) {
      final first = _current.first;
      final df = Offset(first.dx - norm.dx, first.dy - norm.dy);
      final distPx = math.sqrt(df.dx * df.dx + df.dy * df.dy) * rect.width;
      if (distPx < 28) {
        _pendingClose = true;
        return;
      }
    }
    _pendingAnchor = _snapPoint(norm);
  }

  void _onTapUp(TapUpDetails d) {
    final pending = _pendingAnchor;
    final close = _pendingClose;
    _pendingClose = false;
    _pendingAnchor = null;

    if (_draggingAnchor >= 0) {
      setState(() => _draggingAnchor = -1);
      return;
    }
    if (close) {
      _closePolygon();
      return;
    }
    if (pending != null) {
      setState(() {
        _current.add(pending);
        _anchorIdx.add(_current.length - 1);
        _previewPath = null;
      });
    }
  }

  void _onPanStart(DragStartDetails d, Rect rect) {
    // 拖动优先：作废这次 tap 预记的落点 / 闭合意图
    _pendingAnchor = null;
    _pendingClose = false;
    _lastLivewireAt = null; // 新的一笔，节流基准重置

    final norm = _toNormalized(d.localPosition, rect);
    final hit = _hitAnchor(norm, rect);
    if (hit >= 0) {
      setState(() => _draggingAnchor = hit);
      return;
    }

    setState(() => _fingerPos = norm);
  }

  void _onPanUpdate(DragUpdateDetails d, Rect rect) {
    final norm = _toNormalized(d.localPosition, rect);

    // 拖动锚点：直接移动它
    if (_draggingAnchor >= 0) {
      setState(() {
        _current[_draggingAnchor] = norm;
        _fingerPos = norm;
      });
      return;
    }

    final snapped = _snapPoint(norm);

    // 移动阈值节流：指针事件触发极密（每帧多次），
    // 为 1~2 像素的抖动重跑一次最短路纯属浪费。
    // 位移小于 3px 时只更新放大镜位置，不重算路径。
    final last = _lastLivewireAt;
    if (last != null) {
      final mdx = (norm.dx - last.dx) * rect.width;
      final mdy = (norm.dy - last.dy) * rect.height;
      if (mdx * mdx + mdy * mdy < 3 * 3) {
        setState(() => _fingerPos = norm);
        return;
      }
    }
    _lastLivewireAt = norm;

    setState(() {
      _fingerPos = norm;
      // 从"当前路径末点"（没有就是手指起点）到当前点求 livewire 路径
      final from = _current.isNotEmpty ? _current.last : norm;
      final path = _livewire(from, snapped);
      if (path != null && path.length >= 2) {
        _previewPath = path;
      } else {
        // 关闭吸附时退化成自由手绘：把预览路径当成"走过的点串"
        _previewPath = (_previewPath ?? <Offset>[])..add(norm);
      }
    });
  }

  void _onPanEnd() {
    setState(() {
      // 把预览路径**追加**进当前路径。
      // 注意不能把每个点都当锚点 —— livewire 一条路径轻松几百个点，
      // 画笔会把锚点画成一整片白斑，所以只追加为普通路径点，
      // 锚点下标列表不动（用户没"点"它们）。
      final preview = _previewPath;
      if (preview != null && preview.length >= 2) {
        if (_snapToEdge) {
          // 磁性走线：整条追加。跳过 path[0]（= 当前末点，避免重复）
          final start = _current.isEmpty ? 0 : 1;
          _current.addAll(preview.skip(start));
        } else {
          // 自由手绘：抽稀后追加
          for (final p in resampleOffsets(preview, 0.02)) {
            _current.add(p);
          }
        }
      }
      _previewPath = null;
      _fingerPos = null;
      _lastLivewireAt = null;
      _draggingAnchor = -1;
    });
  }

  /// 命中已有锚点。只对**用户显式点下**的锚点（`_anchorIdx`）做命中，
  /// 否则用户想点新位置时会被 livewire 路径上的密集点抢走。
  int _hitAnchor(Offset norm, Rect rect) {
    for (var k = _anchorIdx.length - 1; k >= 0; k--) {
      final i = _anchorIdx[k];
      if (i < 0 || i >= _current.length) continue;
      final a = _current[i];
      final dx = (a.dx - norm.dx) * rect.width;
      final dy = (a.dy - norm.dy) * rect.height;
      if (dx * dx + dy * dy < 26 * 26) return i;
    }
    return -1;
  }

  void _closePolygon() {
    if (_current.length < 3) return;
    setState(() {
      _polygons.add(List<Offset>.from(_current));
      _current.clear();
      _anchorIdx.clear();
      _previewPath = null;
    });
  }

  void _undoLast() {
    setState(() {
      if (_current.isNotEmpty) {
        _current.removeLast();
        // 若删掉的正是锚点，同步修正锚点下标（并丢掉越界的）
        _anchorIdx.removeWhere((i) => i >= _current.length);
      } else if (_polygons.isNotEmpty) {
        _polygons.removeLast();
      }
      _previewPath = null;
    });
  }

  void _clearAll() {
    setState(() {
      _current.clear();
      _anchorIdx.clear();
      _polygons.clear();
      _previewPath = null;
      _fingerPos = null;
      _draggingAnchor = -1;
    });
  }

  Future<void> _finish() async {
    // 还有没闭合的圈 → 自动闭合
    final polys = <List<Offset>>[..._polygons];
    if (_current.length >= 3) polys.add(List<Offset>.from(_current));
    if (polys.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先沿衣服边缘描一圈')));
      return;
    }

    setState(() => _processing = true);
    try {
      final result = await ManualMatteService().cutOut(
        imageFile: widget.imageFile,
        polygons: polys,
        snapToEdge: false, // 这里已经用 livewire 吸附过了，服务端不用再吸
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _processing = false);
      ErrorLog.record('手动抠图', e, s);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('抠图失败，请重试；若多次失败可换个背景更干净的照片')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手动抠图'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _processing ? null : _finish,
            child: const Text('完成'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final rect = _imageRect(constraints.biggest);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _onTapDown(d, rect),
                              onTapUp: _onTapUp,
                              onPanStart: (d) => _onPanStart(d, rect),
                              onPanUpdate: (d) => _onPanUpdate(d, rect),
                              onPanEnd: (_) => _onPanEnd(),
                              child: Stack(
                                children: [
                                  Positioned.fromRect(
                                    rect: rect,
                                    child: Image.file(
                                      widget.imageFile,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _LassoPainter(
                                        polygons: _polygons,
                                        current: _current,
                                        anchors: _anchorIdx
                                            .where((i) => i < _current.length)
                                            .map((i) => _current[i])
                                            .toList(),
                                        preview: _previewPath,
                                        imageRect: rect,
                                        accent: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    _buildToolbar(),
                  ],
                ),
                // 右上角放大镜（手指在画面里时才显示）
                if (_fingerPos != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _Loupe(
                      imageFile: widget.imageFile,
                      imageSize: _imageSize ?? const Size(1, 1),
                      focusNorm: _fingerPos!,
                      accent: AppTheme.primaryColor,
                    ),
                  ),
                if (_processing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              '抠图中，请稍候...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildToolbar() {
    final hasWork = _current.isNotEmpty || _polygons.isNotEmpty;
    final canClose = _current.length >= 3;
    final tip = _snapToEdge
        ? (_polygons.isNotEmpty
              ? '已描 ${_polygons.length} 圈，可继续补描漏掉的部分'
              : _current.isEmpty
              ? '沿衣服边缘点一下落点；也可按住拖动让线自动吸附边缘'
              : '继续点/拖描完一圈，回到起点点一下闭合')
        : (_polygons.isNotEmpty
              ? '已描 ${_polygons.length} 圈，可继续补描漏掉的部分'
              : '手指沿衣服边缘描一圈，松手自动闭合成选区');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tip,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.textSecondaryColor),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: !hasWork || _processing ? null : _undoLast,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤销'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: !hasWork || _processing ? null : _clearAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('清空'),
              ),
              if (canClose && !_processing) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _closePolygon,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('闭合'),
                ),
              ],
              const Spacer(),
              const Text('边缘吸附', style: TextStyle(fontSize: 12)),
              Switch(
                value: _snapToEdge,
                onChanged: _processing
                    ? null
                    : (v) => setState(() => _snapToEdge = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 描边预览画笔：选区外半透明白 + 轮廓线 + 锚点小圆
class _LassoPainter extends CustomPainter {
  final List<List<Offset>> polygons;

  /// 当前这一圈的完整点列（归一化，含点出来的锚点与拖出来的路径点）
  final List<Offset> current;

  /// 其中被用户显式点下的锚点（归一化，画圆点用）
  final List<Offset> anchors;

  /// 悬停时的 livewire 预览（归一化，从 `current` 末点到手指）
  final List<Offset>? preview;
  final Rect imageRect;
  final Color accent;

  const _LassoPainter({
    required this.polygons,
    required this.current,
    required this.anchors,
    required this.preview,
    required this.imageRect,
    required this.accent,
  });

  Offset _map(Offset o) => Offset(
    imageRect.left + o.dx * imageRect.width,
    imageRect.top + o.dy * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paths = <Path>[];
    for (final poly in polygons) {
      if (poly.length < 2) continue;
      paths.add(Path()..addPolygon(poly.map(_map).toList(), true));
    }
    // 当前圈（已落点 + 预览路径）
    final currentPts = <Offset>[];
    currentPts.addAll(current.map(_map));
    if (preview != null) {
      // 预览路径第 0 点是当前末点，跳过避免重复
      currentPts.addAll(preview!.skip(1).map(_map));
    }
    Path? currentPath;
    if (currentPts.length >= 2) {
      currentPath = Path()..addPolygon(currentPts, false);
    }

    final allForMask = <Path>[...paths];
    if (currentPath != null) allForMask.add(currentPath);
    if (allForMask.isNotEmpty) {
      var outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        allForMask.first,
      );
      for (var i = 1; i < allForMask.length; i++) {
        outside = Path.combine(PathOperation.difference, outside, allForMask[i]);
      }
      canvas.drawPath(
        outside,
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }

    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final p in paths) {
      canvas.drawPath(p, stroke);
    }
    if (currentPath != null) canvas.drawPath(currentPath, stroke);

    // 锚点
    final dotFill = Paint()..color = Colors.white;
    final dotEdge = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final a in anchors) {
      final c = _map(a);
      canvas.drawCircle(c, 4.5, dotFill);
      canvas.drawCircle(c, 4.5, dotEdge);
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => true;
}

/// 右上角放大镜：把手指所在区域放大显示，十字准星标出精确位置。
class _Loupe extends StatelessWidget {
  final File imageFile;
  final Size imageSize;
  final Offset focusNorm;
  final Color accent;

  const _Loupe({
    required this.imageFile,
    required this.imageSize,
    required this.focusNorm,
    required this.accent,
  });

  static const double _size = 108;
  static const double _zoom = 3.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 放大图：把 focusNorm 对应的区域放大 _zoom 倍并居中
            Transform.scale(
              scale: _zoom,
              alignment: Alignment(
                // 让关注点在放大后仍落在圆心
                // alignment 取值范围 -1..1，映射像素点 → 圆心
                (focusNorm.dx * 2 - 1) * -1,
                (focusNorm.dy * 2 - 1) * -1,
              ),
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // 十字准星
            CustomPaint(
              painter: _CrosshairPainter(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;
  const _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(c.dx - 9, c.dy), Offset(c.dx + 9, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - 9), Offset(c.dx, c.dy + 9), p);
    canvas.drawCircle(
      c,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}

/// 按最小间距抽稀归一化点列（自由手绘模式下用）。
///
/// 手指每帧都会产生一个点，一个来回轻松上百个；直接当锚点会画出
/// 一大片白斑。这里只保留彼此距离 > [minGap]（归一化）的点。
List<Offset> resampleOffsets(List<Offset> pts, double minGap) {
  if (pts.length < 2) return pts;
  final out = <Offset>[pts.first];
  final g2 = minGap * minGap;
  for (var i = 1; i < pts.length; i++) {
    final a = out.last;
    final b = pts[i];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx * dx + dy * dy >= g2) out.add(b);
  }
  if (out.length == 1) out.add(pts.last);
  return out;
}
