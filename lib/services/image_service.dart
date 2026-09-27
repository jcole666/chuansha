import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 图片服务：拍照、相册选取、旋转
///
/// 抠图功能见 [MattingService]（MODNet AI 自动去背景）
class ImageService {
  final ImagePicker _picker = ImagePicker();

  /// 从相册选择图片
  Future<File?> pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// 拍照
  Future<File?> takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// 顺时针旋转图片 90 度，返回新文件。
  ///
  /// [clockwise] true=顺时针 90°，false=逆时针 90°。
  /// 照片朝向不一致时，旋转后就是正的了。
  Future<File> rotateImage(File imageFile, {bool clockwise = true}) async {
    final original = img.decodeImage(imageFile.readAsBytesSync());
    if (original == null) {
      throw Exception('无法解析图片');
    }

    final rotated = img.copyRotate(
      original,
      angle: clockwise ? 90 : -90,
      interpolation: img.Interpolation.nearest,
    );

    final outDir = imageFile.parent;
    // 后缀必须与实际编码一致：encodeJpg 产出的是 JPEG，
    // 写成 .png 会让上传后的 Content-Type 与实际格式对不上。
    final outPath =
        '${outDir.path}${Platform.pathSeparator}rotated_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File(outPath).writeAsBytesSync(img.encodeJpg(rotated, quality: 90));
    return File(outPath);
  }
}
