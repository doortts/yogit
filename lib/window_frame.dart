import 'package:flutter/foundation.dart';
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
}
