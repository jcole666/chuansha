/// 解析 Supabase 返回的日期
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// 穿搭记录（某一次穿了哪些衣服）
///
/// 一天可以有多个穿搭记录（如"白天"、"晚上"、"约会"）。
/// 对应 Supabase `wear_records` 表。
class WearRecord {
  final String id;
  final String userId;
  final DateTime wearDate; // 穿着日期（只取年月日）
  final String? name; // 穿搭名称/时段（如"白天""晚上""约会"，可空）
  final List<String> itemIds; // 这套穿搭包含的衣服 ID 列表
  final String? note; // 备注（可选）
  final DateTime createdAt;
  final DateTime updatedAt;

  const WearRecord({
    required this.id,
    required this.userId,
    required this.wearDate,
    this.name,
    this.itemIds = const [],
    this.note,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 从 Supabase 行创建
  factory WearRecord.fromJson(Map<String, dynamic> data) {
    return WearRecord(
      id: data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      wearDate: _parseDate(data['wear_date']) ?? DateTime.now(),
      name: data['name'] as String?,
      itemIds: List<String>.from(data['item_ids'] ?? []),
      note: data['note'] as String?,
      createdAt: _parseDate(data['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updated_at']),
    );
  }

  /// 转为 Supabase 行
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'wear_date': wearDate.toIso8601String(),
      'name': name,
      'item_ids': itemIds,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// 创建副本
  ///
  /// 可空字段（name / note）要置 null 必须用显式开关：
  ///   record.copyWith(clearName: true)
  WearRecord copyWith({
    String? id,
    String? userId,
    DateTime? wearDate,
    String? name,
    List<String>? itemIds,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearName = false,
    bool clearNote = false,
  }) {
    return WearRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      wearDate: wearDate ?? this.wearDate,
      name: clearName ? null : (name ?? this.name),
      itemIds: itemIds ?? this.itemIds,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
