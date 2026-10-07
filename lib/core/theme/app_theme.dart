import 'package:flutter/material.dart';

/// 应用主题配置
///
/// 深浅两套配色共用一套结构，只有颜色值不同。
class AppTheme {
  AppTheme._();

  /// 品牌色（深浅色模式共用）
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color secondaryColor = Color(0xFFFF6584);
  static const Color errorColor = Color(0xFFE53935);
  static const Color successColor = Color(0xFF43A047);
  static const Color warningColor = Color(0xFFFFA726);

  // ---------------- 浅色 ----------------
  static const Color surfaceColor = Color(0xFFF8F9FA);
  static const Color backgroundColor = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);

  // ---------------- 深色 ----------------
  static const Color darkBackground = Color(0xFF121216);
  static const Color darkSurface = Color(0xFF1E1E24);
  static const Color darkTextPrimary = Color(0xFFE9E9EC);
  static const Color darkTextSecondary = Color(0xFFA9A9B4);
  static const Color darkTextHint = Color(0xFF75757F);

  /// 获取浅色主题
  static ThemeData get lightTheme => _build(Brightness.light);

  /// 获取深色主题
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? darkBackground : backgroundColor;
    final surface = isDark ? darkSurface : surfaceColor;
    final onBg = isDark ? darkTextPrimary : textPrimary;
    final onBgMuted = isDark ? darkTextSecondary : textSecondary;
    final hint = isDark ? darkTextHint : textHint;

    // 深色下品牌色要提亮一点，否则在深背景上偏暗
    final primary = isDark ? const Color(0xFF8F88FF) : primaryColor;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        primary: primary,
        secondary: secondaryColor,
        surface: surface,
        error: errorColor,
        // 卡片/次级容器
        surfaceContainerHighest: isDark
            ? const Color(0xFF26262E)
            : const Color(0xFFEFEFF2),
      ),
      scaffoldBackgroundColor: bg,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 底部导航
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: primary,
        unselectedItemColor: hint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),

      // 卡片
      cardTheme: CardThemeData(
        color: isDark ? darkSurface : backgroundColor,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // 浮动按钮
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
      ),

      // 输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: hint, fontSize: 14),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(fontSize: 13, color: onBg),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // 分割线
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF2E2E36) : const Color(0xFFE8E8EC),
      ),

      // 文本
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: onBg,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: onBg,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onBg,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: onBg,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: onBg),
        bodyMedium: TextStyle(fontSize: 14, color: onBg),
        bodySmall: TextStyle(fontSize: 12, color: onBgMuted),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onBg,
        ),
        labelSmall: TextStyle(fontSize: 11, color: hint),
      ),
    );
  }
}

/// 主题感知的颜色扩展
///
/// 之前各处直接写 `AppTheme.textSecondary`（#757575），
/// 在深色背景上对比度只有约 4.0，不达标。改用这些 getter
/// 让颜色随主题走。
extension AppThemeColors on BuildContext {
  /// 次级文字（说明、副标题）
  Color get textSecondaryColor => Theme.of(this).colorScheme.onSurfaceVariant;

  /// 更弱的提示文字
  Color get textHintColor =>
      Theme.of(this).colorScheme.onSurfaceVariant.withValues(alpha: 0.65);

  /// 浅灰底（占位块、进度条底色）
  Color get subtleFillColor =>
      Theme.of(this).colorScheme.surfaceContainerHighest;

  /// 页面背景
  Color get pageBackgroundColor => Theme.of(this).scaffoldBackgroundColor;
}
