import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App colours. The brand colour is "Hellelfenbein" (RAL 1015), the ivory of
/// German taxis, on charcoal (dark) or warm white (light).
class Palette {
  const Palette({required this.brightness, required this.ink, required this.muted,
    required this.canvas, required this.surface, required this.field, required this.border,
    required this.tile, required this.primary, required this.onPrimary, required this.accent,
    required this.money, required this.heroStart, required this.heroEnd});
  final Brightness brightness;
  final Color ink, muted, canvas, surface, field, border, tile;
  final Color primary, onPrimary, accent, money, heroStart, heroEnd;
}

const taxiIvory = Color(0xFFE6D2B5);

const darkPalette = Palette(
  brightness: Brightness.dark,
  ink: Color(0xFFF3EFE7), muted: Color(0xFFA8A296),
  canvas: Color(0xFF111315), surface: Color(0xFF1B1E22), field: Color(0xFF15181B),
  border: Color(0xFF2E333A), tile: Color(0xFF181B1F),
  primary: taxiIvory, onPrimary: Color(0xFF16181B), accent: Color(0xFFF2B544),
  money: Color(0xFF3DDC97), heroStart: Color(0xFF3A3326), heroEnd: Color(0xFF1B1E22),
);

const lightPalette = Palette(
  brightness: Brightness.light,
  ink: Color(0xFF1B1D20), muted: Color(0xFF6B655C),
  canvas: Color(0xFFF5F1E8), surface: Color(0xFFFFFFFF), field: Color(0xFFEFE9DD),
  border: Color(0xFFDDD3C2), tile: Color(0xFFFFFFFF),
  primary: Color(0xFF1F2328), onPrimary: Color(0xFFF5F1E8), accent: Color(0xFFB7791F),
  money: Color(0xFF178A5B), heroStart: Color(0xFFEADBC0), heroEnd: Color(0xFFF7F1E6),
);

/// The palette of the current build. Set by LogbookApp before building pages.
Palette palette = darkPalette;

/// Light/dark choice of the driver, stored per device.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const _themeKey = 'theme_mode';

void loadThemeMode(SharedPreferences preferences) {
  themeMode.value = ThemeMode.values.asNameMap()[preferences.getString(_themeKey)] ?? ThemeMode.system;
}

Future<void> saveThemeMode(SharedPreferences preferences, ThemeMode mode) async {
  themeMode.value = mode;
  await preferences.setString(_themeKey, mode.name);
}

Palette paletteFor(ThemeMode mode, Brightness platform) => switch (mode) {
  ThemeMode.light => lightPalette,
  ThemeMode.dark => darkPalette,
  ThemeMode.system => platform == Brightness.light ? lightPalette : darkPalette,
};

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(seedColor: taxiIvory, brightness: p.brightness).copyWith(
    primary: p.primary, onPrimary: p.onPrimary, surface: p.surface, onSurface: p.ink,
    secondary: p.money, tertiary: p.accent);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.canvas,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45),
    ).apply(bodyColor: p.ink, displayColor: p.ink),
    cardTheme: CardThemeData(color: p.surface, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: p.ink, minimumSize: const Size(0, 52),
      side: BorderSide(color: p.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    navigationBarTheme: NavigationBarThemeData(
      height: 76, backgroundColor: p.surface,
      indicatorColor: p.primary.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 12, color: p.ink,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500))),
    appBarTheme: AppBarTheme(backgroundColor: p.canvas, foregroundColor: p.ink, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: p.primary, foregroundColor: p.onPrimary,
      minimumSize: const Size(0, 56),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary, foregroundColor: p.onPrimary),
  );
}
