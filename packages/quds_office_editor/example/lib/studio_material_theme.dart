import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Keeps Material menus, dialogs and fields in the same palette as the canvas.
/// Document colors are handled separately by the editor's display-only theme.
ThemeData studioMaterialTheme(
  ThemeData base, {
  required OfficeTheme office,
  required Color accent,
  required bool dark,
  bool highContrast = false,
}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: dark ? Brightness.dark : Brightness.light,
        contrastLevel: highContrast ? 1 : 0,
      ).copyWith(
        surface: office.chromeFill,
        onSurface: office.chromeText,
        onSurfaceVariant: office.headerText,
        surfaceContainerHighest: office.frozenFill,
        outlineVariant: office.gridLine,
      );
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    brightness: scheme.brightness,
    colorScheme: scheme,
    textTheme: text,
    iconTheme: IconThemeData(color: scheme.onSurface),
    canvasColor: scheme.surface,
    cardColor: scheme.surface,
    scaffoldBackgroundColor: office.canvasBackground,
    dividerColor: scheme.outlineVariant,
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyMedium,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.onSurface,
      selectionColor: office.selectionFill,
      selectionHandleColor: scheme.primary,
    ),
  );
}
