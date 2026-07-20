/// Identidade visual SAFEBOAT (mesma do protótipo web e dos outros módulos).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SB {
  static const bg = Color(0xFF1E2A49);
  static const card = Color(0xFF2A3757);
  static const card2 = Color(0xFF243052);
  static const card3 = Color(0xFF1A2340);
  static const green = Color(0xFFA5CB74);
  static const amber = Color(0xFFFFD738);
  static const red = Color(0xFFE0524B);
  static const muted = Color(0xFF8E9BB8);
  static const white = Color(0xFFFFFFFF);
  static const water = Color(0xFF25709B);

  static const greenSoft = Color(0x28A5CB74);
  static const amberSoft = Color(0x26FFD738);
  static const redSoft = Color(0x28E0524B);

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: green,
        surface: bg,
        error: red,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: white,
        displayColor: white,
      ),
    );
  }
}
