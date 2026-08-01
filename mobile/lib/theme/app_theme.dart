import 'package:flutter/material.dart';

/// Voyplan's shared visual identity. One cohesive dark theme so every default
/// widget (buttons, inputs, dialogs, date/time pickers, snackbars, menus)
/// looks consistent instead of falling back to Material's light defaults.
class Voy {
  // Core palette
  static const bg = Color(0xFF0E1116);
  static const surface = Color(0xFF161B22);
  static const surface2 = Color(0xFF1B212C);
  static const hairline = Color(0xFF242C38);
  static const ink = Color(0xFFEDEFF3);
  static const sub = Color(0xFF8B97A7);

  // Accents
  static const brand = Color(0xFF22C7C0); // teal
  static const brandDeep = Color(0xFF0FA7A0);
  static const violet = Color(0xFF8F81F2);
  static const pink = Color(0xFFF472B6);
  static const amber = Color(0xFFFBBF24);
  static const coral = Color(0xFFFF8672);
  static const success = Color(0xFF34D27B);
  static const danger = Color(0xFFFB7185);
  static const info = Color(0xFF60A5FA);

  static const gradient = LinearGradient(
    colors: [brand, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData dark(TextTheme textTheme) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: brand,
      onPrimary: Color(0xFF04211F),
      secondary: violet,
      onSecondary: Colors.white,
      tertiary: pink,
      onTertiary: Colors.white,
      error: danger,
      onError: Color(0xFF3A0A12),
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surface2,
      outline: hairline,
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: surface,
      textTheme: textTheme.apply(bodyColor: ink, displayColor: ink),
      dividerColor: hairline,
      splashFactory: InkRipple.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: ink),
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: const Color(0xFF04211F),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: const Color(0xFF04211F),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brand, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: hairline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: const TextStyle(color: sub),
        labelStyle: const TextStyle(color: sub),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border(hairline),
        enabledBorder: border(hairline),
        focusedBorder: border(brand, 1.6),
        errorBorder: border(danger),
        focusedErrorBorder: border(danger, 1.6),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: ink, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface2,
        contentTextStyle: const TextStyle(color: ink),
        actionTextColor: brand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: hairline)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        side: const BorderSide(color: hairline),
        labelStyle: const TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
      drawerTheme: const DrawerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(color: ink),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brand : sub),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brand.withValues(alpha: 0.4) : surface2),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: surface,
        dialBackgroundColor: surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}
