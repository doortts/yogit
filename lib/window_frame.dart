import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PreviewPlacement { closed, right, bottom, left }

class WindowFrameController extends ChangeNotifier {
  WindowFrameController({
    MethodChannel channel = const MethodChannel('yogit/window'),
    WidgetsBinding? binding,
  }) : _channel = channel,
       _binding = binding ?? WidgetsBinding.instance {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final WidgetsBinding _binding;

  /// 멈춘 프레임을 되살린 횟수. 창 하나가 겪는 상태라 프로세스 전체가 같은 값을
  /// 본다. 0이 아니면 이 실행에서 화면이 굳은 적이 있다는 뜻이고, 사용자가 "가끔
  /// 멈춰요"라고 할 때 짚을 수 있는 유일한 흔적이다.
  static final frameRevivals = ValueNotifier<int>(0);

  PreviewPlacement previewPlacement = PreviewPlacement.closed;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'windowBecameVisible') _reviveStalledFrames();
    return null;
  }

  /// 창이 다시 보이는데도 프레임이 꺼져 있으면, 가려짐에서 돌아온 사실을 embedder가
  /// 놓친 것이다. 그대로 두면 예약된 프레임이 영영 돌지 않아 입력은 들어가는데
  /// 화면만 굳는다. 진짜로 가려진 창의 정상적인 절전과 다투지 않도록, 꺼져 있을
  /// 때만 lifecycle을 되돌려 파이프라인을 다시 세운다.
  void _reviveStalledFrames() {
    if (_binding.framesEnabled) return;
    frameRevivals.value++;
    debugPrint(
      'yogit: 창이 보이는데 프레임이 꺼져 있어 되살립니다 '
      '(${frameRevivals.value}번째).',
    );
    _binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

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
