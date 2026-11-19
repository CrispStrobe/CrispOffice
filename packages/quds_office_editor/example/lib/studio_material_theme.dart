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
    scaffoldBackgroundColor: office.canvasBackground,
    dividerColor: scheme.outlineVariant,
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
      fillColor: scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.onSurface,
      selectionColor: office.selectionFill,
      selectionHandleColor: scheme.primary,
    ),
  );
}
