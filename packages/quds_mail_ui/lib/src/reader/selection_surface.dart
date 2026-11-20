import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'presentation.dart';

/// Read-only decoded text selection painted directly by a custom RenderBox.
/// Host chrome may wrap this leaf in Focus and scrolling; no editable text or
/// browser/HTML widget participates in message rendering.
class MailSelectionSurface extends LeafRenderObjectWidget {
  const MailSelectionSurface({
    super.key,
    required this.controller,
    required this.textDirection,
    this.style = const TextStyle(fontSize: 16, height: 1.4),
    this.textScaler = TextScaler.noScaling,
    this.linkColor,
    this.onLink,
    this.onCopy,
    this.onFocusRequest,
  });
  final MailReaderController controller;
  final TextDirection textDirection;
  final TextStyle style;
  final Color? linkColor;
  final TextScaler textScaler;
  final ValueChanged<Uri>? onLink;
  final VoidCallback? onCopy;
  final VoidCallback? onFocusRequest;

  @override
  RenderMailSelectionSurface createRenderObject(BuildContext context) =>
      RenderMailSelectionSurface(
        controller: controller,
        direction: textDirection,
        style: style.copyWith(
          color: style.color ?? Theme.of(context).colorScheme.onSurface,
        ),
        linkColor: linkColor ?? Theme.of(context).colorScheme.primary,
        textScaler: textScaler,
        onLink: onLink,
        onCopy: onCopy,
        onFocusRequest: onFocusRequest,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMailSelectionSurface renderObject,
  ) {
    renderObject
      ..controller = controller
      ..direction = textDirection
      ..style = style.copyWith(
        color: style.color ?? Theme.of(context).colorScheme.onSurface,
      )
      ..linkColor = linkColor ?? Theme.of(context).colorScheme.primary
      ..textScaler = textScaler
      ..onLink = onLink
      ..onCopy = onCopy
      ..onFocusRequest = onFocusRequest;
  }
}

class RenderMailSelectionSurface extends RenderBox {
  RenderMailSelectionSurface({
    required this._controller,
    required TextDirection direction,
    required this._style,
    Color linkColor = const Color(0xff1a57a8),
    required TextScaler textScaler,
    this.onLink,
    this.onCopy,
    this.onFocusRequest,
  }) : _linkColor = linkColor,
       _direction = direction,
       _textScaler = textScaler,
       _painter = TextPainter(
         textDirection: direction,
         textScaler: textScaler,
       ) {
    _tap = TapGestureRecognizer()..onTapUp = _onTap;
    _drag = PanGestureRecognizer()
      ..onStart = (details) {
        _anchor = _position(details.localPosition);
        _controller.select(TextSelection.collapsed(offset: _anchor));
      }
      ..onUpdate = (details) => _controller.select(
        TextSelection(
          baseOffset: _anchor,
          extentOffset: _position(details.localPosition),
        ),
      );
    _longPress = LongPressGestureRecognizer()
      ..onLongPressStart = (details) {
        _controller.selectWordAt(_position(details.localPosition));
        _anchor = _controller.selection.baseOffset;
      }
      ..onLongPressMoveUpdate = (details) => _controller.select(
        TextSelection(
          baseOffset: _anchor,
          extentOffset: _position(details.localPosition),
        ),
      );
  }

  MailReaderController _controller;
  TextDirection _direction;
  TextStyle _style;
  Color _linkColor;
  Color get linkColor => _linkColor;
  TextStyle get textStyle => _style;
  set linkColor(Color value) {
    if (value == _linkColor) return;
    _linkColor = value;
    markNeedsLayout();
  }

  TextScaler _textScaler;
  final TextPainter _painter;
  late final TapGestureRecognizer _tap;
  late final PanGestureRecognizer _drag;
  late final LongPressGestureRecognizer _longPress;
  MailReaderPresentation? _lastPresentation;
  int _anchor = 0;
  ValueChanged<Uri>? onLink;
  VoidCallback? onCopy;
  VoidCallback? onFocusRequest;

  MailReaderController get controller => _controller;
  set controller(MailReaderController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(_changed);
    _controller = value;
    if (attached) _controller.addListener(_changed);
    _lastPresentation = null;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    markNeedsLayout();
  }

  void _changed() {
    if (!identical(_lastPresentation, _controller.presentation)) {
      markNeedsLayout();
    }
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_changed);
  }

  @override
  void detach() {
    _controller.removeListener(_changed);
    super.detach();
  }

  InlineSpan _span() => TextSpan(
    style: _style,
    children: [
      for (final run in _controller.presentation.runs)
        TextSpan(
          text: _controller.decodedText.substring(run.start, run.end),
          style: TextStyle(
            fontWeight: run.bold ? FontWeight.bold : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            color: run.link == null ? null : _linkColor,
            decoration: run.link == null ? null : TextDecoration.underline,
          ),
        ),
    ],
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 800.0;
    final painter = TextPainter(
      text: _span(),
      textDirection: _direction,
      textScaler: _textScaler,
    )..layout(maxWidth: width);
    final result = constraints.constrain(Size(width, painter.height));
    painter.dispose();
    return result;
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 800.0;
    _painter
      ..text = _span()
      ..textDirection = _direction
      ..textScaler = _textScaler
      ..layout(maxWidth: width);
    _lastPresentation = _controller.presentation;
    size = constraints.constrain(Size(width, _painter.height));
  }

  /// Local paint bounds of the selection, for host search navigation.
  Rect? get selectionRect {
    final boxes = _painter.getBoxesForSelection(_controller.selection);
    if (boxes.isEmpty) return null;
    return boxes
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
  }

  int _position(Offset local) => _painter
      .getPositionForOffset(local)
      .offset
      .clamp(0, _controller.decodedText.length);

  void _onTap(TapUpDetails details) {
    final position = _position(details.localPosition);
    _controller.select(TextSelection.collapsed(offset: position));
    for (final run in _controller.presentation.runs) {
      if (position >= run.start && position < run.end && run.link != null) {
        onLink?.call(run.link!);
        break;
      }
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      onFocusRequest?.call();
      _tap.addPointer(event);
      if (event.kind == ui.PointerDeviceKind.mouse ||
          event.kind == ui.PointerDeviceKind.stylus) {
        _drag.addPointer(event);
      } else {
        _longPress.addPointer(event);
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    void highlight(TextSelection selection, Color color) {
      for (final box in _painter.getBoxesForSelection(selection)) {
        canvas.drawRect(box.toRect(), Paint()..color = color);
      }
    }

    for (final match in _controller.searchMatches) {
      highlight(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
        const Color(0x66ffd65a),
      );
    }
    highlight(_controller.selection, const Color(0x663c86dc));
    _painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isReadOnly = true
      ..isTextField = true
      ..label = 'Decoded message, read only'
      ..value = _controller.decodedText
      ..textDirection = _direction
      ..textSelection = _controller.selection
      ..onSetSelection = _controller.select;
    if (onCopy != null) config.onCopy = onCopy;
  }

  @override
  void dispose() {
    _tap.dispose();
    _drag.dispose();
    _longPress.dispose();
    _painter.dispose();
    super.dispose();
  }
}
