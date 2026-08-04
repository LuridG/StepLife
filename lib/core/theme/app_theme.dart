import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF10B981); // Emerald
  static const Color secondaryColor = Color(0xFF6366F1); // Indigo
  static const Color accentCyan = Color(0xFF06B6D4); // Cyan Accent
  static const Color backgroundColor = Color(0xFF0B1329); // Deep Midnight
  static const Color cardBgColor = Color(0x1AFFFFFF);

  /// 全局输入框提示文字：淡灰、小字号，避免喧宾夺主（用于深色对话框）
  static const TextStyle hintStyle = TextStyle(
    color: Colors.white38,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
  );

  /// 文本框浮动标签：品牌绿 + 加粗 + 阴影，与用户输入内容明显区分（深色对话框通用）
  static const TextStyle inputLabelStyle = TextStyle(
    color: Color(0xFF34D399),
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    shadows: [
      Shadow(color: Colors.black45, blurRadius: 2.5, offset: Offset(0, 1)),
    ],
  );

  /// 浅色主题下的标签样式（白底页面用深一点的品牌绿保证可读性）
  static const TextStyle inputLabelStyleLight = TextStyle(
    color: Color(0xFF047857),
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    shadows: [
      Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
    ],
  );


  /// 浅色主题：页面背景保留品牌深色渐变，对话框保持深色毛玻璃以兼容现有硬编码文字
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFEFF3FA),
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1A2333),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1A2333),
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF334155)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black.withAlpha(15), width: 1),
        ),
      ),
      // 对话框保留深色毛玻璃，保证现有白色文字可读
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(35), width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF94A3B8),
        selectedLabelStyle: TextStyle(fontSize: 12),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        elevation: 10,
        type: BottomNavigationBarType.fixed,
        enableFeedback: true,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w400),
        labelStyle: inputLabelStyleLight,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: Color(0xFF111C38),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      cardTheme: CardThemeData(
        color: cardBgColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(25), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(35), width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF090D16),
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white38,
        selectedLabelStyle: TextStyle(fontSize: 12),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        elevation: 10,
        type: BottomNavigationBarType.fixed,
        enableFeedback: true,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: hintStyle,
        labelStyle: inputLabelStyle,
      ),
    );
  }
}
