import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'settings_service.dart';

class VoiceService extends ChangeNotifier {
  static final VoiceService instance = VoiceService._();
  VoiceService._();

  static const MethodChannel _channel = MethodChannel('com.pulseagent.app/agent');

  bool isListening = false;
  bool sttAvailable = true;
  String lastRecognizedWords = '';
  void Function(String recognizedText)? _activeCallback;
  void Function(String finalText)? _finalCallback;

  Future<void> init() async {
    sttAvailable = true;
  }

  void handleNativeSpeechResult(String rawWords, bool isFinal) {
    var text = rawWords.trim();
    if (SettingsService.instance.wakeWordJarvisEnabled) {
      final lower = text.toLowerCase();
      if (lower.startsWith('джарвис')) {
        text = text.substring('джарвис'.length).trim();
      }
    }
    if (text.isNotEmpty) {
      lastRecognizedWords = text;
      _activeCallback?.call(text);
    }
    if (isFinal) {
      isListening = false;
      if (text.isNotEmpty) {
        _finalCallback?.call(text);
      }
    }
    notifyListeners();
  }

  Future<void> startListening({
    required void Function(String recognizedText) onResult,
    void Function(String finalText)? onFinal,
  }) async {
    _activeCallback = onResult;
    _finalCallback = onFinal;
    isListening = true;
    notifyListeners();
    try {
      await _channel.invokeMethod('startListening', {'locale': 'ru-RU'});
    } catch (_) {
      isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } catch (_) {}
    isListening = false;
    notifyListeners();
  }

  Future<void> speak(String message) async {
    if (!SettingsService.instance.voiceResponsesEnabled) return;
    if (message.trim().isEmpty) return;
    try {
      await _channel.invokeMethod('speakText', {'text': message});
    } catch (_) {}
  }

  Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod('stopSpeaking');
    } catch (_) {}
  }
}
