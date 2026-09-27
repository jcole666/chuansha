import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../services/manual_matte_service.dart';

/// 手动抠图页面
///
/// 用户用手指沿衣服边缘描一圈，松手自动闭合成选区，圈内保留、圈外填白。
/// 可以描多圈（比如袖子和主体分开了），结果取并集。
///
/// 返回抠好的图片 [File]，取消返回 null。
class ManualMattePage extends StatefulWidget {
  final File imageFile;

  const ManualMattePage({super.key, required this.imageFile});

  @override
  State<ManualMattePage> createState() => _ManualMattePageState();
}

class _ManualMattePageState extends State<ManualMattePage> {
  /// 已完成的轮廓（归一化坐标）
  final List<List<Offset>> _polygons = [];

  /// 正在描的这一条
  List<Offset>? _current;

  Size? _imageSize;
  bool _snapToEdge = true;
  bool _processing = false;

  /// 采样间隔（归一化距离），太小会攒出几千个点拖慢重绘
  static const double _minStep = 0.004;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final file = widget.imageFile;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      if (!mounted) return;
      setState(() => _imageSize = size);
    } catch (_) {
      // 读不到尺寸就退化成 1:1 处理
      if (!mounted) return;
      setState(() => _imageSize = const Size(1, 1));
    }
  }

  /// 图片在容器里的实际显示矩形（等价 BoxFit.contain + 居中）
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

  void _onPanStart(DragStartDetails d, Rect rect) {
    setState(() => _current = [_toNormalized(d.localPosition, rect)]);
  }

  void _onPanUpdate(DragUpdateDetails d, Rect rect) {
    final p = _toNormalized(d.localPosition, rect);
    final cur = _current;
    if (cur == null) return;
    final last = cur.last;
    final dx = p.dx - last.dx;
    final dy = p.dy - last.dy;
    if (dx * dx + dy * dy < _minStep * _minStep) return;
    setState(() => cur.add(p));
  }

  void _onPanEnd() {
    final cur = _current;
    if (cur == null) return;
    setState(() {
      if (cur.length >= 3) _polygons.add(cur);
      _current = null;
    });
  }

  Future<void> _finish() async {
    final file = widget.imageFile;
    if (_polygons.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先沿衣服边缘描一圈')));
      return;
    }

    setState(() => _processing = true);
    try {
      final result = await ManualMatteService().cutOut(
        imageFile: file,
        polygons: _polygons,
        snapToEdge: _snapToEdge,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('抠图失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;

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
      body: size == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final rect = _imageRect(constraints.biggest);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
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
                                      painter: _OutlinePainter(
                                        polygons: _polygons,
                                        current: _current,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
            _polygons.isEmpty
                ? '手指沿衣服边缘描一圈，松手自动闭合成选区'
                : '已描 ${_polygons.length} 圈，可继续补描漏掉的部分',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _polygons.isEmpty || _current != null
                    ? null
                    : () => setState(() => _polygons.removeLast()),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤销'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _polygons.isEmpty && _current == null
                    ? null
                    : () => setState(() {
                        _polygons.clear();
                        _current = null;
                      }),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('清空'),
              ),
              const Spacer(),
              const Text('边缘吸附', style: TextStyle(fontSize: 13)),
              Switch(
                value: _snapToEdge,
                onChanged: (v) => setState(() => _snapToEdge = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 描边预览：选区外半透明白（模拟最终效果），轮廓描主色线
class _OutlinePainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final List<Offset>? current;
  final Rect imageRect;
  final Color accent;

  const _OutlinePainter({
    required this.polygons,
    required this.current,
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
    final cur = current;
    if (cur != null && cur.length >= 2) {
      paths.add(Path()..addPolygon(cur.map(_map).toList(), true));
    }
    if (paths.isEmpty) return;

    // 选区外 → 半透明白（逐个 difference，保证多圈是并集而不是挖洞）
    var outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      paths.first,
    );
    for (var i = 1; i < paths.length; i++) {
      outside = Path.combine(PathOperation.difference, outside, paths[i]);
    }
    canvas.drawPath(
      outside,
      Paint()..color = Colors.white.withValues(alpha: 0.58),
    );

    // 轮廓线
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final p in paths) {
      canvas.drawPath(p, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter oldDelegate) => true;
}
