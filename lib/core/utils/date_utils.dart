import 'package:intl/intl.dart';

/// 日期格式化工具
class DateUtils {
  /// 格式化日期为 "yyyy-MM-dd"
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// 格式化日期为 "MM月dd日"
  static String formatDateChinese(DateTime date) {
    return DateFormat('MM月dd日').format(date);
  }

  /// 格式化日期为友好的相对时间（如 "3天前"）
  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 30) {
      return '${diff.inDays}天前';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}个月前';
    } else {
      return '${(diff.inDays / 365).floor()}年前';
    }
  }

  /// 判断两个日期是否为同一天
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
