import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/error_log.dart';
import '../../../../services/ai_matting_service.dart';
import '../../../../services/image_service.dart';
import '../../../../services/matting_service.dart';
import 'manual_matte_page.dart';

/// 换图流程页（给已录入的衣物重新选图 / 重新抠图）
///
/// 两步：
/// 1. 选来源（拍照 / 相册）
/// 2. 预览 + 选择抠图方式（智能 / 手动 / 跳过）
///
/// 完成后 pop 返回最终图片 [File]，取消返回 null。
///
/// 之前编辑页完全没有图片相关代码 —— 照片拍糊了或抠图不满意，
/// 只能删掉重录，分类、标签、价格、穿着记录全丢。
class ChangeItemImagePage extends StatefulWidget {
  const ChangeItemImagePage({super.key});

  @override
  State<ChangeItemImagePage> createState() => _ChangeItemImagePageState();
}

class _ChangeItemImagePageState extends State<ChangeItemImagePage> {
  final _imageService = ImageService();
  final _mattingService = MattingService();

  File? _file;
  bool _isLoading = false;
  String? _error;

  Future<void> _pick({required bool fromCamera}) async {
    try {
      final file = fromCamera
          ? await _imageService.takePhoto()
          : await _imageService.pickFromGallery();
      if (file == null || !mounted) return;
      setState(() {
        _file = file;
        _error = null;
      });
    } catch (e, s) {
      ErrorLog.record('选择图片', e, s);
      if (!mounted) return;
      setState(() => _error = '选择图片失败，请重试');
    }
  }

  Future<void> _autoMatte() async {
    final file = _file;
    if (file == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // ① 优先 AI 分割模型（效果接近醒图智能抠图）
    try {
      if (await AiMattingService.instance.isAvailable()) {
        final matted = await AiMattingService.instance.removeBackground(file);
        if (!mounted) return;
        setState(() {
          _file = matted;
          _isLoading = false;
        });
        return;
      }
    } catch (e, s) {
      // AI 失败 → 静默降级到颜色抠图，只记日志
      ErrorLog.record('AI抠图-降级', e, s);
    }

    // ② 降级：旧的纯色背景洪水填充
    try {
      final matted = await _mattingService.removeBackground(file);
      if (!mounted) return;
      setState(() {
        _file = matted;
        _isLoading = false;
      });
    } on MattingException catch (e) {
      // 抠图失败是有意设计的降级引导（如「衣服占满画面，请用手动抠图」），
      // 保留 MattingException 的引导文案，但不把原始异常透出给用户。
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (e, s) {
      ErrorLog.record('抠图', e, s);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '抠图失败，请重试，或改用「手动抠图」';
      });
    }
  }

  Future<void> _manualMatte() async {
    final file = _file;
    if (file == null) return;

    final result = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => ManualMattePage(imageFile: file)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _file = result;
      _error = null;
    });
  }

  Future<void> _rotate() async {
    final file = _file;
    if (file == null) return;

    setState(() => _isLoading = true);
    try {
      final rotated = await _imageService.rotateImage(file);
      if (!mounted) return;
      setState(() {
        _file = rotated;
        _isLoading = false;
      });
    } catch (e, s) {
      ErrorLog.record('旋转图片', e, s);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '旋转失败，请重试';
      });
    }
  }

  void _confirm() {
    final file = _file;
    if (file == null) return;
    Navigator.of(context).pop(file);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_file == null ? '重新选择图片' : '处理图片'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _file == null ? _buildSourceSelector() : _buildPreview(),
    );
  }

  Widget _buildSourceSelector() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 80,
            color: AppTheme.primaryColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 24),
          Text('重新选择图片', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 32),
          SizedBox(
            width: 220,
            child: ElevatedButton.icon(
              onPressed: () => _pick(fromCamera: true),
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: OutlinedButton.icon(
              onPressed: () => _pick(fromCamera: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册选择'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 350,
                color: context.subtleFillColor,
                child: Image.file(_file!, fit: BoxFit.contain),
              ),
              if (_isLoading)
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
          const SizedBox(height: 24),
          Text(
            '纯色背景用「智能抠图」；背景复杂就用「手动抠图」描一圈',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                              _file = null;
                              _error = null;
                            }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新选择'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _rotate,
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('旋转'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _autoMatte,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('智能抠图'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _manualMatte,
                      icon: const Icon(Icons.gesture, size: 18),
                      label: const Text('手动抠图'),
                      style: ElevatedButton.styleFrom(
                        // 跟随主题，避免深色模式下出现刺眼的白按钮
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isLoading ? null : _confirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('就用这张'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
