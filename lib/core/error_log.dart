import 'dart:collection';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// 一条运行日志
class ErrorLogEntry {
  final DateTime time;
  final String tag;
  final String message;
  final String? stack;

  const ErrorLogEntry({
    required this.time,
    required this.tag,
    required this.message,
    this.stack,
  });

  String get formatted {
    final t = time.toIso8601String().substring(11, 19);
    final buf = StringBuffer('[$t] $tag: $message');
    if (stack != null && stack!.isNotEmpty) {
      // 只留前几帧，够定位即可
      final lines = stack!.split('\n').take(4).join('\n    ');
      buf.write('\n    $lines');
    }
    return buf.toString();
  }
}

/// 轻量本地错误日志
///
/// 线上问题排查用：把运行期异常与业务失败记在内存环形缓冲里，
/// 用户可以在「设置 → 运行日志」里查看并复制出来反馈。
///
/// 为什么不做成 Sentry/Crashlytics：那类服务需要联网上报与额外依赖，
/// 现阶段（还在真机联调）本地日志更直接可用。接入正式上报时，
/// 只要在 [record] 里再加一条上报调用即可。
class ErrorLog {
  ErrorLog._();

  /// 最多保留多少条
  static const int maxEntries = 200;

  static final ListQueue<ErrorLogEntry> _entries = ListQueue<ErrorLogEntry>();

  /// 日志变化通知（日志页用它刷新）
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<ErrorLogEntry> get entries => _entries.toList(growable: false);

  static bool get isEmpty => _entries.isEmpty;

  /// 记录一条日志
  static void record(String tag, Object error, [StackTrace? stack]) {
    // debug 下同时打到控制台，方便连着 IDE 看
    if (kDebugMode) {
      debugPrint('[ErrorLog][$tag] $error');
    }

    _entries.addLast(
      ErrorLogEntry(
        time: DateTime.now(),
        tag: tag,
        message: error.toString(),
        stack: stack?.toString(),
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    revision.value++;
  }

  /// 记录一条普通信息（非异常，用于追踪关键流程）
  static void info(String tag, String message) {
    record(tag, message);
  }

  /// 清空
  static void clear() {
    _entries.clear();
    revision.value++;
  }

  /// 导出为纯文本（供「复制」按钮使用）
  static String export() {
    if (_entries.isEmpty) return '（暂无日志）';
    return _entries.map((e) => e.formatted).join('\n');
  }

  /// 安装全局异常钩子
  ///
  /// 在 `main()` 里调用一次。
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record('FlutterError', details.exceptionAsString(), details.stack);
      previous?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record('Uncaught', error, stack);
      // 返回 true 表示已处理，避免应用直接崩掉
      return true;
    };
  }
}
