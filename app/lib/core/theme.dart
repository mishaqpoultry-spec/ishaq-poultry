import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand colours: deep emerald, soft neutral surfaces, clear red/green for money.
class AppColors {
  static const green = Color(0xFF0F7A45); // primary emerald
  static const greenDark = Color(0xFF0A5C33);
  static const greenSoft = Color(0xFFE7F5EC);
  static const surface = Color(0xFFF6F7F9); // page background
  static const field = Color(0xFFF2F4F6); // input fill
  static const border = Color(0xFFE5E8EC);
  static const text = Color(0xFF16202A);
  static const textMuted = Color(0xFF6B7684);
  static const paid = Color(0xFF138A4B); // received / paid amounts
  static const due = Color(0xFFD03A3A); // outstanding / overdue amounts

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14955A), Color(0xFF0A5C33)],
  );
}

/// Subtle elevation used for cards and tiles.
const softShadow = [
  BoxShadow(color: Color(0x0F101828), blurRadius: 16, offset: Offset(0, 6)),
  BoxShadow(color: Color(0x08101828), blurRadius: 2, offset: Offset(0, 1)),
];

/// Money and weights line up in columns with tabular digits.
const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: Brightness.light).copyWith(
    primary: AppColors.green,
    onPrimary: Colors.white,
    secondary: AppColors.greenDark,
    surface: Colors.white,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.field,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    error: AppColors.due,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = _textTheme(base.textTheme);

  final radius12 = BorderRadius.circular(12);
  final inputBorder = OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide.none);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: text,
    primaryTextTheme: text,
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.green, width: 1.6)),
      errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.due, width: 1.2)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.due, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: text.bodyMedium?.copyWith(color: AppColors.textMuted),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: AppColors.green, fontWeight: FontWeight.w600),
      hintStyle: text.bodyMedium?.copyWith(color: AppColors.textMuted),
      helperStyle: text.bodySmall?.copyWith(color: AppColors.textMuted),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.green,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.green,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.greenSoft,
        selectedForegroundColor: AppColors.greenDark,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AppColors.greenSoft,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text),
      subtitleTextStyle: text.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.4),
      iconColor: AppColors.textMuted,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.greenSoft,
      selectedIconTheme: const IconThemeData(color: AppColors.greenDark),
      unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: AppColors.greenDark, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
      dataTextStyle: text.bodyMedium,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.green),
  );
}

/// Plus Jakarta Sans — a clean, modern geometric font. Falls back to the
/// platform font automatically if it cannot be loaded (e.g. offline first run).
TextTheme _textTheme(TextTheme base) {
  final t = GoogleFonts.plusJakartaSansTextTheme(base).apply(bodyColor: AppColors.text, displayColor: AppColors.text);
  return t.copyWith(
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}
