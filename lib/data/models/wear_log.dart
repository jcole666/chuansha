/// 穿搭日志模型
///
/// 参见 PRD 5.3 节
class WearLog {
  final String id;
  final String userId;
  final DateTime date;              // 日期（不含时间）
  final List<String> itemIds;       // 当日单品列表
  final String? outfitId;           // 关联 Outfit ID
  final String? photoUrl;           // 当日穿搭照片
  final double? temperature;        // 当日温度
  final String? weatherCondition;   // 天气状况
  final String? note;               // 备注
  final DateTime createdAt;

  const WearLog({
    required this.id,
    required this.userId,
    required this.date,
    this.itemIds = const [],
    this.outfitId,
    this.photoUrl,
    this.temperature,
    this.weatherCondition,
    this.note,
    required this.createdAt,
  });

  factory WearLog.fromJson(Map<String, dynamic> data) {
    return WearLog(
      id: data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      date: _parseDate(data['date']) ?? DateTime.now(),
      itemIds: List<String>.from(data['item_ids'] ?? []),
      outfitId: data['outfit_id'] as String?,
      photoUrl: data['photo_url'] as String?,
      temperature: (data['temperature'] as num?)?.toDouble(),
      weatherCondition: data['weather_condition'] as String?,
      note: data['note'] as String?,
      createdAt: _parseDate(data['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': date.toIso8601String(),
      'item_ids': itemIds,
      'outfit_id': outfitId,
      'photo_url': photoUrl,
      'temperature': temperature,
      'weather_condition': weatherCondition,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}
