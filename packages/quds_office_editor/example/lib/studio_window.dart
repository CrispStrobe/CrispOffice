import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window chrome for the example host (Office-style custom frame).
class StudioWindow {
  StudioWindow._();

  static var supported = false;
  static var maximized = false;
  static var fullscreen = false;

  static const MethodChannel _channel = MethodChannel('crispoffice/window');

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  // AppKit draws these even when the window-manager plugin cannot initialize.
  static bool get usesNativeTrafficLights => isMacOS;

  static bool get usesCaptionButtons => supported && !isMacOS;

  static bool get isDesktop {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  static Future<void> bootstrap({
    String title = 'CrispOffice',
    Size size = const Size(1280, 720),
    Size minimumSize = const Size(880, 560),
  }) async {
    if (!isDesktop) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      final WindowOptions options = WindowOptions(
        size: size,
        minimumSize: minimumSize,
        center: true,
        backgroundColor: Color(0x00000000),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: isMacOS,
        title: title,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: isMacOS,
        );
        // The host checks every open workspace for unsaved edits first.
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      });
      maximized = await windowManager.isMaximized();
      fullscreen = await windowManager.isFullScreen();
      supported = true;
    } catch (_) {
      supported = false;
    }
  }

  static Future<void> setTitle(String title) async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.setTitle(title);
    } catch (_) {}
  }

  static Future<void> drag() async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.startDragging();
    } catch (_) {}
  }

  static Future<void> minimize() async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  static Future<void> show() async {
    if (!supported) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  static Future<void> toggleMaximize() async {
    if (!supported) {
      return;
    }
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        maximized = false;
      } else {
        await windowManager.maximize();
        maximized = true;
      }
    } catch (_) {}
  }

  static Future<void> close() async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.close();
    } catch (_) {}
  }

  static Future<void> _closeApproved() async {
    if (!supported) return;
    await windowManager.setPreventClose(false);
    try {
      await windowManager.close();
    } finally {
      // macOS keeps the app and window controller alive for Dock reopen.
      if (isMacOS) await windowManager.setPreventClose(true);
    }
  }

  /// OS-level fullscreen (covers the monitor, not just the app window).
  static Future<void> setFullScreen(bool value) async {
    if (!supported) {
      return;
    }
    try {
      final bool current = await windowManager.isFullScreen();
      if (current == value) {
        fullscreen = value;
        return;
      }
      await windowManager.setFullScreen(value);
      fullscreen = value;
    } catch (_) {}
  }

  static Widget wrap(Widget child) {
    if (!supported) {
      return child;
    }
    return _StudioWindowFrame(child: child);
  }
}

/// Keeps [StudioWindow.maximized] in sync with the native window.
class StudioWindowScope extends StatefulWidget {
  const StudioWindowScope({
    super.key,
    required this.child,
    required this.onChanged,
    required this.onCloseRequested,
  });

  final Widget child;
  final VoidCallback onChanged;
  final Future<bool> Function() onCloseRequested;

  @override
  State<StudioWindowScope> createState() => _StudioWindowScopeState();
}

class _StudioWindowScopeState extends State<StudioWindowScope>
    with WindowListener {
  bool _handlingClose = false;
  bool _closingApproved = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (StudioWindow.supported) {
      windowManager.addListener(this);
      _listening = true;
    }
    if (StudioWindow.isMacOS) {
      StudioWindow._channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'confirmQuit') return _confirmClose();
        throw MissingPluginException('Unknown window request: ${call.method}');
      });
    }
  }

  @override
  void dispose() {
    if (_listening) {
      windowManager.removeListener(this);
    }
    if (StudioWindow.isMacOS) StudioWindow._channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<bool> _confirmClose() async {
    if (_handlingClose || !mounted) return false;
    _handlingClose = true;
    try {
      return await widget.onCloseRequested();
    } finally {
      _handlingClose = false;
    }
  }

  @override
  void onWindowClose() {
    if (!_closingApproved) unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    if (await _confirmClose() && mounted) {
      _closingApproved = true;
      try {
        await StudioWindow._closeApproved();
      } finally {
        _closingApproved = false;
      }
    }
  }

  @override
  void onWindowMaximize() {
    StudioWindow.maximized = true;
    widget.onChanged();
  }

  @override
  void onWindowUnmaximize() {
    StudioWindow.maximized = false;
    widget.onChanged();
  }

  @override
  void onWindowEnterFullScreen() {
    StudioWindow.fullscreen = true;
    widget.onChanged();
  }

  @override
  void onWindowLeaveFullScreen() {
    StudioWindow.fullscreen = false;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _StudioWindowFrame extends StatefulWidget {
  const _StudioWindowFrame({required this.child});

  final Widget child;

  @override
  State<_StudioWindowFrame> createState() => _StudioWindowFrameState();
}

class _StudioWindowFrameState extends State<_StudioWindowFrame>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    StudioWindow.fullscreen = true;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    StudioWindow.fullscreen = false;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool locked = StudioWindow.fullscreen;
    return DragToResizeArea(
      resizeEdgeSize: locked ? 0 : 5,
      enableResizeEdges: locked ? const <ResizeEdge>[] : null,
      child: SizedBox.expand(child: widget.child),
    );
  }
}
