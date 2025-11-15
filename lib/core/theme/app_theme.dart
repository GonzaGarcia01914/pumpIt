import 'package:flutter/material.dart';

class AppTheme {
  static const Color _background = Color(0xFF040407);
  static const Color _surface = Color(0xFF0A0C12);
  static const Color _surfaceAlt = Color(0xFF141723);
  static const Color _border = Color(0x26FFFFFF);
  static const Color _primary = Color(0xFF8A7CFF);
  static const Color _secondary = Color(0xFF53C5FF);

  static const List<Color> _accentGradient = [
    Color(0xFF5B8CFF),
    Color(0xFF9A64FF),
  ];

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.dark,
      surface: _surface,
      primary: _primary,
      secondary: _secondary,
      tertiary: _surfaceAlt,
    );

    final baseTextTheme = Typography.whiteMountainView.apply(
      fontFamily: 'Inter',
      displayColor: Colors.white,
      bodyColor: Colors.white.withValues(alpha: 0.9),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      canvasColor: _background,
      colorScheme: scheme,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        titleSpacing: 0,
        centerTitle: false,
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: _surfaceAlt,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(32)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ).copyWith(
              overlayColor: _hoverOverlay(Colors.white),
              shadowColor: _hoverShadow(_primary),
              elevation: _hoverElevation(rest: 0, hovered: 10, pressed: 4),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ).copyWith(
              side: _outlinedSide(
                base: Colors.white.withValues(alpha: 0.25),
                hover: _primary.withValues(alpha: 0.8),
              ),
              overlayColor: _hoverOverlay(_primary),
              backgroundColor: _backgroundTint(
                rest: Colors.transparent,
                hover: Colors.white.withValues(alpha: 0.05),
                pressed: Colors.white.withValues(alpha: 0.08),
                disabled: Colors.white.withValues(alpha: 0.02),
              ),
              shadowColor: _hoverShadow(
                _secondary,
                restAlpha: 0.1,
                hoverAlpha: 0.35,
              ),
              elevation: _hoverElevation(rest: 0, hovered: 6, pressed: 2),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ).copyWith(
              overlayColor: _hoverOverlay(Colors.white),
              backgroundColor: _backgroundTint(
                rest: Colors.transparent,
                hover: Colors.white.withValues(alpha: 0.05),
                pressed: Colors.white.withValues(alpha: 0.1),
                disabled: Colors.white.withValues(alpha: 0.02),
              ),
              shadowColor: _hoverShadow(
                _secondary,
                restAlpha: 0,
                hoverAlpha: 0.25,
              ),
              elevation: _hoverElevation(rest: 0, hovered: 4, pressed: 2),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
            ).copyWith(
              backgroundColor: _backgroundTint(
                rest: Colors.white.withValues(alpha: 0.08),
                hover: Colors.white.withValues(alpha: 0.14),
                pressed: Colors.white.withValues(alpha: 0.2),
                disabled: Colors.white.withValues(alpha: 0.04),
              ),
              overlayColor: _hoverOverlay(Colors.white),
              shadowColor: _hoverShadow(
                _secondary,
                restAlpha: 0.1,
                hoverAlpha: 0.4,
              ),
              elevation: _hoverElevation(rest: 0, hovered: 10, pressed: 6),
            ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceAlt.withValues(alpha: 0.6),
        labelStyle: baseTextTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.7),
        ),
        floatingLabelStyle: TextStyle(
          color: _secondary.withValues(alpha: 0.95),
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: _secondary.withValues(alpha: 0.8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        selectedColor: _primary.withValues(alpha: 0.25),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.white70,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _primary.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      dividerColor: Colors.white.withValues(alpha: 0.07),
      tabBarTheme: TabBarThemeData(
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: LinearGradient(
            colors: _accentGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.4),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceAlt,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: baseTextTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: baseTextTheme.bodySmall,
      ),
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
    );
  }

  static WidgetStateProperty<Color?> _hoverOverlay(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: 0.22);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: 0.12);
      }
      return null;
    });
  }

  static WidgetStateProperty<Color?> _hoverShadow(
    Color base, {
    double restAlpha = 0.25,
    double hoverAlpha = 0.45,
    double pressedAlpha = 0.35,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: pressedAlpha);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.withValues(alpha: hoverAlpha);
      }
      return base.withValues(alpha: restAlpha);
    });
  }

  static WidgetStateProperty<double?> _hoverElevation({
    double rest = 0,
    double hovered = 6,
    double pressed = 2,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return 0;
      }
      if (states.contains(WidgetState.pressed)) {
        return pressed;
      }
      if (states.contains(WidgetState.hovered)) {
        return hovered;
      }
      return rest;
    });
  }

  static WidgetStateProperty<BorderSide?> _outlinedSide({
    required Color base,
    required Color hover,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: Colors.white.withValues(alpha: 0.1));
      }
      if (states.contains(WidgetState.hovered)) {
        return BorderSide(color: hover, width: 1.4);
      }
      return BorderSide(color: base);
    });
  }

  static WidgetStateProperty<Color?> _backgroundTint({
    Color? rest,
    Color? hover,
    Color? pressed,
    Color? disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabled;
      }
      if (states.contains(WidgetState.pressed)) {
        return pressed ?? hover ?? rest;
      }
      if (states.contains(WidgetState.hovered)) {
        return hover ?? rest;
      }
      return rest;
    });
  }
}
