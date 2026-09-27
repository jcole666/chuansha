/// 衣物状态枚举
enum ClothingStatus {
  /// 已洗好（干净，可穿）
  clean,

  /// 待洗（脏了，需要洗）
  dirty,

  /// 干洗中
  dryCleaning,

  /// 在洗衣房
  inLaundry;

  /// 中文显示名称
  String get label {
    switch (this) {
      case ClothingStatus.clean:
        return '已洗好';
      case ClothingStatus.dirty:
        return '待洗';
      case ClothingStatus.dryCleaning:
        return '干洗中';
      case ClothingStatus.inLaundry:
        return '在洗衣房';
    }
  }

  /// 从字符串解析
  static ClothingStatus fromString(String value) {
    return ClothingStatus.values.firstWhere(
      (e) => e.name == value || e.label == value,
      orElse: () => ClothingStatus.clean,
    );
  }
}
