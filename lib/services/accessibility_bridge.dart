import 'package:flutter/services.dart';
import 'voice_service.dart';

class AccessibilityBridge {
  static const MethodChannel _channel = MethodChannel('com.pulseagent.app/agent');

  MethodChannel get rawChannel => _channel;

  void registerNativeCallbacks({
    required void Function(String reason) onEmergencyStop,
    required void Function(String goal) onScheduledGoalTriggered,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEmergencyStop') {
        final reason = call.arguments?.toString() ?? 'Экстренная остановка';
        onEmergencyStop(reason);
      } else if (call.method == 'onScheduledGoalTriggered') {
        final goal = call.arguments?.toString() ?? '';
        if (goal.isNotEmpty) {
          onScheduledGoalTriggered(goal);
        }
      } else if (call.method == 'onSpeechResult') {
        final rawArgs = call.arguments;
        final Map<dynamic, dynamic>? map =
            rawArgs is Map ? Map<dynamic, dynamic>.from(rawArgs) : null;
        final text = map?['text']?.toString() ?? rawArgs?.toString() ?? '';
        final isFinal = map?['isFinal'] is bool ? map!['isFinal'] as bool : true;
        VoiceService.instance.handleNativeSpeechResult(text, isFinal);
      }
      return null;
    });
  }

  Future<bool> isAccessibilityEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> toggleFloatingOverlay(bool show) async {
    try {
      await _channel.invokeMethod('toggleOverlayButton', {'show': show});
    } catch (_) {}
  }

  Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (_) {}
  }

  Future<String> getScreenTree() async {
    try {
      final tree = await _channel.invokeMethod<String>('getScreenTree');
      return tree ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> getActivePackage() async {
    try {
      final pkg = await _channel.invokeMethod<String>('getActivePackage');
      return pkg ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> getActivePackageName() => getActivePackage();

  Future<bool> tapByIndex(int index, {num? fallbackX, num? fallbackY}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('tapElement', {
        'index': index,
        'x': fallbackX?.toInt(),
        'y': fallbackY?.toInt(),
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> tapCoordinates(int x, int y) async {
    try {
      final ok = await _channel.invokeMethod<bool>('tapElement', {
        'index': -1,
        'x': x,
        'y': y,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> inputText(int index, String text, {bool emulateGestureTyping = false}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('inputText', {
        'index': index,
        'text': text,
        'emulateTyping': emulateGestureTyping,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> inputTextByIndex(int index, String text, {bool emulateGestureTyping = false}) =>
      inputText(index, text, emulateGestureTyping: emulateGestureTyping);

  Future<bool> scroll(String direction) async {
    try {
      final ok = await _channel.invokeMethod<bool>('scrollScreen', {
        'direction': direction,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> scrollScreen(String direction) => scroll(direction);

  Future<bool> performGlobalNav(String navAction) async {
    try {
      final ok = await _channel.invokeMethod<bool>('globalNav', {
        'action': navAction,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> longPress(int index, {int durationMs = 800}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('longPressElement', {
        'index': index,
        'durationMs': durationMs,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> longPressByIndex(int index, {int durationMs = 800}) =>
      longPress(index, durationMs: durationMs);

  Future<bool> swipe({
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    int durationMs = 350,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('swipeGesture', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> swipeGesture({
    required num x1,
    required num y1,
    required num x2,
    required num y2,
    int durationMs = 350,
  }) =>
      swipe(
        x1: x1.toInt(),
        y1: y1.toInt(),
        x2: x2.toInt(),
        y2: y2.toInt(),
        durationMs: durationMs,
      );

  Future<bool> waitForText(String text, {int timeoutSeconds = 10}) async {
    final target = text.trim().toLowerCase();
    if (target.isEmpty) return true;
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds.clamp(1, 60)));
    while (DateTime.now().isBefore(deadline)) {
      final tree = await getScreenTree();
      if (tree.toLowerCase().contains(target)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  Future<String> takeScreenshot() async {
    try {
      final path = await _channel.invokeMethod<String>('takeScreenshot');
      return path ?? 'Скриншот выполнен';
    } catch (e) {
      return 'Ошибка скриншота: $e';
    }
  }
}
