/// 应用异常基类
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// 网络异常
class NetworkException extends AppException {
  const NetworkException({super.message = '网络连接不可用', super.code});
}

/// 服务器异常
class ServerException extends AppException {
  const ServerException({super.message = '服务器错误', super.code});
}

/// 图片处理异常
class ImageProcessException extends AppException {
  const ImageProcessException({super.message = '图片处理失败', super.code});
}

/// 数据不存在异常
class NotFoundException extends AppException {
  const NotFoundException({super.message = '数据不存在', super.code});
}

/// 权限异常
class PermissionException extends AppException {
  const PermissionException({super.message = '权限不足', super.code});
}
