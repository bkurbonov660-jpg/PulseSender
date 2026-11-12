import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../secrets.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const List<String> availableModels = [
    'openrouter/free',
    'deepseek/deepseek-r1:free',
    'meta-llama/llama-3.3-70b-instruct:free',
    'google/gemini-2.0-flash-exp:free',
  ];

  String selectedModel = 'openrouter/free';
  String customApiKey = '';
  bool isApiKeyConfirmed = false;
  int maxSteps = 30;
  int maxMinutes = 5;
  int maxDailyTasks = 100;
  bool confirmDangerousActions = true;
  bool voiceResponsesEnabled = true;
  bool wakeWordJarvisEnabled = false;
  bool blockCameraAtNight = true;
  List<String> blacklistedPackages = [
    'com.sberbankmobile',
    'com.idamob.tinkoff.android',
    'tj.alif.mobi',
    'com.dc.next',
    'com.eskhata.online',
  ];
  Set<String> alwaysAllowedActions = {};

  String get effectiveApiKey =>
      customApiKey.trim().isNotEmpty ? customApiKey.trim() : Secrets.openRouterKey.trim();

  bool get hasValidApiKey => effectiveApiKey.isNotEmpty;

  String get maskedApiKey {
    final k = effectiveApiKey;
    if (k.isEmpty) return 'Не задан';
    if (k.length <= 12) return '***';
    return '${k.substring(0, 9)}...${k.substring(k.length - 4)}';
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    selectedModel = p.getString('selected_model') ?? 'openrouter/free';
    if (!availableModels.contains(selectedModel)) {
      selectedModel = 'openrouter/free';
    }
    customApiKey = p.getString('custom_api_key') ?? '';
    isApiKeyConfirmed = p.getBool('api_key_confirmed') ?? effectiveApiKey.isNotEmpty;
    maxSteps = (p.getInt('max_steps') ?? 30).clamp(10, 50);
    maxMinutes = (p.getInt('max_minutes') ?? 5).clamp(1, 10);
    maxDailyTasks = p.getInt('max_daily_tasks') ?? 100;
    confirmDangerousActions = p.getBool('confirm_dangerous') ?? true;
    voiceResponsesEnabled = p.getBool('voice_tts') ?? true;
    wakeWordJarvisEnabled = p.getBool('wake_word_jarvis') ?? false;
    blockCameraAtNight = p.getBool('block_camera_night') ?? true;
    blacklistedPackages = p.getStringList('blacklisted_packages') ?? blacklistedPackages;
    alwaysAllowedActions = (p.getStringList('always_allowed_actions') ?? const []).toSet();
    notifyListeners();
  }

  Future<void> updateModel(String model) async {
    selectedModel = model;
    final p = await SharedPreferences.getInstance();
    await p.setString('selected_model', model);
    notifyListeners();
  }

  Future<void> updateApiKey(String key, {bool confirmed = true}) async {
    customApiKey = key.trim();
    isApiKeyConfirmed = confirmed && customApiKey.isNotEmpty;
    final p = await SharedPreferences.getInstance();
    await p.setString('custom_api_key', customApiKey);
    await p.setBool('api_key_confirmed', isApiKeyConfirmed);
    notifyListeners();
  }

  Future<void> updateMaxSteps(int steps) async {
    maxSteps = steps.clamp(10, 50);
    final p = await SharedPreferences.getInstance();
    await p.setInt('max_steps', maxSteps);
    notifyListeners();
  }

  Future<void> updateMaxMinutes(int minutes) async {
    maxMinutes = minutes.clamp(1, 10);
    final p = await SharedPreferences.getInstance();
    await p.setInt('max_minutes', maxMinutes);
    notifyListeners();
  }

  Future<void> updateConfirmDangerous(bool val) async {
    confirmDangerousActions = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('confirm_dangerous', val);
    notifyListeners();
  }

  Future<void> allowActionForever(String actionType) async {
    alwaysAllowedActions.add(actionType);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('always_allowed_actions', alwaysAllowedActions.toList());
    notifyListeners();
  }

  Future<void> updateVoiceResponses(bool val) async {
    voiceResponsesEnabled = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('voice_tts', val);
    notifyListeners();
  }

  Future<void> updateWakeWordJarvis(bool val) async {
    wakeWordJarvisEnabled = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('wake_word_jarvis', val);
    notifyListeners();
  }

  Future<void> updateBlacklistedPackages(List<String> list) async {
    blacklistedPackages = list;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('blacklisted_packages', list);
    notifyListeners();
  }

  Future<void> resetAll() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    await init();
  }
}
