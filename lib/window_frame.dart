import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PreviewPlacement { closed, right, bottom, left }

class WindowFrameController extends ChangeNotifier {
  WindowFrameController({
    MethodChannel channel = const MethodChannel('yogit/window'),
  }) : _channel = channel;

  final MethodChannel _channel;

  PreviewPlacement previewPlacement = PreviewPlacement.closed;

  Future<void> setPreview(PreviewPlacement placement) async {
    if (placement == previewPlacement) return;
    previewPlacement = placement;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setPreview', placement.name);
    } on MissingPluginException {
      // Dart-only platforms keep the Flutter layout behavior.
    }
  }

  /// The native folder chooser: the picked path, or null when the user cancels.
  Future<String?> pickRepository() async {
    try {
      return await _channel.invokeMethod<String>('pickRepository');
    } on MissingPluginException {
      return null;
    }
  }

  /// The window controls the toolbar draws itself. Dart-only platforms have no
  /// window to command, so each is a no-op there.
  Future<void> closeWindow() => _invoke('closeWindow');

  Future<void> minimizeWindow() => _invoke('minimizeWindow');

  Future<void> toggleZoom() => _invoke('toggleZoom');

  /// Hands the current mouse event to AppKit so the toolbar drags the window.
  Future<void> startDrag() => _invoke('startDrag');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native window here; nothing to do.
    }
  }
}

/// The window controls the native titlebar no longer draws, in macOS order.
/// Every yogit window draws its own, so every window can be closed.
class WindowButtons extends StatelessWidget {
  const WindowButtons({required this.controller, super.key});

  final WindowFrameController controller;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      WindowButton(
        key: const Key('window-close'),
        color: const Color(0xFFFF5F57),
        glyph: '×',
        onTap: () => unawaited(controller.closeWindow()),
      ),
      const SizedBox(width: 8),
      WindowButton(
        key: const Key('window-minimize'),
        color: const Color(0xFFFEBC2E),
        glyph: '−',
        onTap: () => unawaited(controller.minimizeWindow()),
      ),
      const SizedBox(width: 8),
      WindowButton(
        key: const Key('window-zoom'),
        color: const Color(0xFF28C840),
        glyph: '+',
        onTap: () => unawaited(controller.toggleZoom()),
      ),
    ],
  );
}

class WindowButton extends StatefulWidget {
  const WindowButton({
    required this.color,
    required this.glyph,
    required this.onTap,
    super.key,
  });

  final Color color;
  final String glyph;
  final VoidCallback onTap;

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: 12,
        height: 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        ),
        child: _hovered
            ? Text(
                widget.glyph,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    ),
  );
}
