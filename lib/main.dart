import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/assistant_hub_service.dart';
import 'services/automation_service.dart';
import 'services/history_service.dart';
import 'services/scenario_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await SettingsService.instance.init();
  await ScenarioService.instance.init();
  await AssistantHubService.instance.init();
  await HistoryService.instance.init();
  await VoiceService.instance.init();
  await AutomationService.instance.init();

  runApp(const PulseAgentApp());
}
