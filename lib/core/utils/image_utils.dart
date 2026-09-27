/// 图片相关工具方法
class ImageUtils {
  ImageUtils._();

  /// 生成唯一的图片文件名
  static String generateImageName(String userId, {String prefix = 'item'}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${prefix}_${userId}_$timestamp';
  }

  /// Firebase Storage 原图路径
  static String originalImagePath(String userId, String imageName) {
    return 'users/$userId/original/$imageName.jpg';
  }

  /// Firebase Storage 处理后的图片路径
  static String processedImagePath(String userId, String imageName) {
    return 'users/$userId/processed/$imageName.png';
  }
}
