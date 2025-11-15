import 'package:flutter/material.dart';

class NivioTheme {
  // Netflix Colors
  static const Color netflixRed = Color(0xFFE50914);
  static const Color netflixBlack = Color(0xFF141414);
  static const Color netflixDarkGrey = Color(0xFF2F2F2F);
  static const Color netflixGrey = Color(0xFF808080);
  static const Color netflixLightGrey = Color(0xFFB3B3B3);
  static const Color netflixWhite = Color(0xFFFFFFFF);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: netflixBlack,
    primaryColor: netflixRed,
    colorScheme: const ColorScheme.dark(
      primary: netflixRed,
      secondary: netflixRed,
      surface: netflixDarkGrey,
      surfaceContainer: netflixDarkGrey,
    ),
    
    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: netflixRed,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    ),
    
    // Text Theme
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: netflixWhite,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        color: netflixWhite,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
      displaySmall: TextStyle(
        color: netflixWhite,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: netflixWhite,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: netflixWhite,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: netflixWhite,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(
        color: netflixWhite,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: netflixLightGrey,
        fontSize: 14,
      ),
      bodySmall: TextStyle(
        color: netflixGrey,
        fontSize: 12,
      ),
    ),
    
    // Input Decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: netflixDarkGrey,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: netflixGrey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    
    // Elevated Button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: netflixRed,
        foregroundColor: netflixWhite,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    
    // Card
    cardTheme: const CardThemeData(
      color: netflixDarkGrey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    
    // Progress Indicator
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: netflixRed,
    ),
  );
}
