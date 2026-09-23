import 'package:flutter/material.dart';

/// VoyPlan's shared visual identity. One cohesive dark theme so every default
/// widget (buttons, inputs, dialogs, date/time pickers, snackbars, menus)
/// looks consistent instead of falling back to Material's light defaults.
class Voy {
  // Core Classic Royal palette
  static const bg = Color(0xFF070D18);
  static const surface = Color(0xFF0D1726);
  static const surface2 = Color(0xFF132238);
  static const hairline = Color(0xFF1F314D);
  static const ink = Color(0xFFFDFBF7); // Warm Ivory
  static const sub = Color(0xFF94A3B8); // Slate Subtext

  // Royal Accents
  static const gold = Color(0xFFD4AF37); // Champagne Gold
  static const goldLight = Color(0xFFF3E5AB);
  static const goldMuted = Color(0xFFC5A880);
  static const navy = Color(0xFF0A192F); // Deep Royal Navy
  static const navyLight = Color(0xFF172A45);

  // Accents & Compatibility aliases
  static const brand =
      Color(0xFFD4AF37); // Champagne gold is the primary brand accent
  static const brandDeep = Color(0xFFAA8A39);
  static const teal = Color(0xFF22C7C0);
  static const violet = Color(0xFF8F81F2);
  static const pink = Color(0xFFF472B6);
  static const amber = Color(0xFFFBBF24);
  static const coral = Color(0xFFFF8672);
  static const success = Color(0xFF34D27B);
  static const danger = Color(0xFFFB7185);
  static const info = Color(0xFF60A5FA);

  static const gradient = LinearGradient(
    colors: [gold, goldMuted],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const royalGradient = LinearGradient(
    colors: [Color(0xFF0A192F), Color(0xFF172A45)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Classic Royal Serif style helper for headings, titles, and hero elements
  static TextStyle royalSerif({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w700,
    Color color = ink,
    double letterSpacing = 0.2,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Playfair Display',
      fontFamilyFallback: const ['Cinzel', 'Georgia', 'serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

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
        titleTextStyle:
            TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: const Color(0xFF04211F),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: const Color(0xFF04211F),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: brand,
            textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: hairline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        titleTextStyle: const TextStyle(
            color: ink, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(color: ink, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: hairline)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        side: const BorderSide(color: hairline),
        labelStyle: const TextStyle(
            color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
      drawerTheme: const DrawerThemeData(
          backgroundColor: surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(color: ink),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? brand : sub),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? brand.withValues(alpha: 0.4)
                : surface2),
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

  /// Bright dashboard variant that preserves VoyPlan's cyan, gold, and violet
  /// accents while providing a true light Material surface hierarchy.
  static ThemeData light(TextTheme textTheme) {
    const page = Color(0xFFF3F8FC);
    const lightSurface = Color(0xFFFFFFFF);
    const lightSurface2 = Color(0xFFE8F1F8);
    const lightInk = Color(0xFF10243D);
    const lightSub = Color(0xFF52677D);
    const lightOutline = Color(0xFFC8D9E7);
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0284C7),
      onPrimary: Colors.white,
      secondary: Color(0xFF635BCE),
      onSecondary: Colors.white,
      tertiary: Color(0xFFB83280),
      onTertiary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: lightSurface,
      onSurface: lightInk,
      surfaceContainerHighest: lightSurface2,
      outline: lightOutline,
    );

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      canvasColor: lightSurface,
      textTheme: textTheme.apply(bodyColor: lightInk, displayColor: lightInk),
      dividerColor: lightOutline,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: lightInk),
        titleTextStyle: TextStyle(
          color: lightInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightInk,
          side: const BorderSide(color: lightOutline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface2,
        hintStyle: const TextStyle(color: lightSub),
        labelStyle: const TextStyle(color: lightSub),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border(lightOutline),
        enabledBorder: border(lightOutline),
        focusedBorder: border(scheme.primary, 1.6),
        errorBorder: border(danger),
        focusedErrorBorder: border(danger, 1.6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: const TextStyle(
          color: lightInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: lightInk, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: lightInk,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: goldLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lightOutline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightSurface2,
        side: const BorderSide(color: lightOutline),
        labelStyle: const TextStyle(
          color: lightInk,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      drawerTheme: const DrawerThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(color: lightInk),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : lightSub,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.35)
              : lightSurface2,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: lightSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: lightSurface,
        dialBackgroundColor: lightSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}
