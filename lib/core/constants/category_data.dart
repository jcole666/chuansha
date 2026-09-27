/// 衣服预设分类体系
///
/// 大标签 → 小标签（两级）
/// 季节 / 场合 / 风格 / 色系 / 穿着频率 独立标签维度
class CategoryData {
  CategoryData._();

  /// 大标签列表（固定顺序）
  static const List<String> mainCategories = [
    '上衣',
    '外套',
    '下装',
    '连衣裙',
    '西服套装',
    '运动套装',
    '睡衣套装',
    '鞋',
    '配饰',
    '内衣',
  ];

  /// 小标签映射（大标签 → 小标签列表）
  static const Map<String, List<String>> subCategories = {
    '上衣': ['短袖', '长袖', '衬衫', '卫衣', '针织衫', '背心'],
    '外套': ['西装', '夹克', '风衣', '大衣', '牛仔外套'],
    '下装': ['短裤', '牛仔长裤', '休闲长裤', '西装长裤', '半裙'],
    '连衣裙': ['吊带裙', '短裙', '长裙', '衬衫裙'],
    '西服套装': ['成套西装', '正式套装'],
    '运动套装': ['卫衣套装', '运动服套装', '健身服'],
    '睡衣套装': ['睡衣', '家居服套装'],
    '鞋': ['运动鞋', '平底鞋', '靴子', '凉鞋', '拖鞋'],
    '配饰': ['帽子', '围巾', '包', '腰带', '首饰', '袜子'],
    '内衣': ['内衣', '打底'],
  };

  /// 女性专属大标签（男性不显示）
  static const Set<String> femaleOnlyCategories = {'连衣裙'};

  /// 女性专属小标签（男性不显示）
  static const Set<String> femaleOnlySubCategories = {
    '半裙',        // 下装
    '吊带裙', '短裙', '长裙', '衬衫裙',  // 连衣裙
    '内衣',        // 内衣
  };

  /// 季节标签（含四季通用）
  static const List<String> seasonTags = ['春', '夏', '秋', '冬', '四季通用'];

  /// 场合标签
  static const List<String> occasionTags = [
    '通勤', '日常', '约会', '运动', '正式', '居家',
  ];

  /// 风格标签
  static const List<String> styleTags = [
    '休闲', '职场', '甜美', '酷感', '复古', '运动',
  ];

  /// 穿着频率
  static const List<String> wearFrequency = ['常穿', '偶尔穿', '待处理'];

  /// 色系（供 ColorData 引用）
  static const List<String> colorFamilies = [
    '黑色系', '白色系', '灰色系', '红色系', '橙色系',
    '黄色系', '绿色系', '蓝色系', '紫色系', '粉色系',
    '棕色系', '米色系', '牛仔蓝', '卡其色系', '彩色',
  ];

  /// 根据性别获取大标签列表
  static List<String> getMainCategoriesForGender({required bool isMale}) {
    if (isMale) {
      return mainCategories.where((c) => !femaleOnlyCategories.contains(c)).toList();
    }
    return mainCategories;
  }

  /// 根据性别和主分类获取小标签
  static List<String> getSubCategoriesForGender({
    required String mainCategory,
    required bool isMale,
  }) {
    final all = subCategories[mainCategory] ?? [];
    if (isMale) {
      return all.where((s) => !femaleOnlySubCategories.contains(s)).toList();
    }
    return all;
  }

  /// 根据主分类获取小标签列表（不限性别，向后兼容）
  static List<String> getSubCategories(String mainCategory) {
    return subCategories[mainCategory] ?? [];
  }

  /// 根据小标签推断大标签
  static String? inferMainCategory(String subCategory) {
    for (final entry in subCategories.entries) {
      if (entry.value.contains(subCategory)) {
        return entry.key;
      }
    }
    return null;
  }
}
