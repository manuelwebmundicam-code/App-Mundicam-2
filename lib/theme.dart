import 'package:flutter/material.dart';

/// Colores de la app estilo Mundicam
class AppColors {
  static const Color primary = Color(0xFFA60909);      // rojo  Mundicam
  static const Color accent = Color(0xFFB71C1C);       // rojo oscuro
  static const Color background = Color(0xFFFFFFFF);   // fondo blanco
  static const Color textPrimary = Color(0xFF000000);  // texto negro principal
  static const Color textSecondary = Color(0xFF424242);// texto secundario
}

/// Tema global de la app
class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    primaryColor: AppColors.primary,
    hintColor: AppColors.accent,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Oswald',  // Oswald
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
      ),
    ),
    appBarTheme: const AppBarTheme(
      color: AppColors.primary,
      elevation: 2,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 20,
        fontFamily: 'Oswald', // fuente consistente cMBIAR POR MONSERRAT CUANDO ESTEMOS SEGUROS QUE ES ESA
      ),
      iconTheme: IconThemeData(
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          fontFamily: 'Oswald',
        ),
      ),
    ),
  );
}