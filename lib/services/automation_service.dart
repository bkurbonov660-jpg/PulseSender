import 'package:flutter/services.dart';
import 'system_actions_service.dart';

class AutomationService {
  static final AutomationService instance = AutomationService._();
  AutomationService._();

  static const MethodChannel _channel = MethodChannel('com.pulseagent.app/agent');
  final SystemActionsService _systemActions = SystemActionsService();

  Future<void> init() async {}

  Future<void> registerPeriodicAutomation({
    required String uniqueName,
    required String goalPrompt,
    Duration frequency = const Duration(hours: 24),
  }) async {
    try {
      await _channel.invokeMethod('schedulePeriodicGoal', {
        'name': uniqueName,
        'goal': goalPrompt,
        'intervalSeconds': frequency.inSeconds.clamp(60, 86400 * 7),
      });
    } catch (_) {}
  }

  Future<void> scheduleOneShotTask({
    required String goalPrompt,
    required Duration delay,
  }) async {
    await _systemActions.scheduleExactGoal(
      goal: goalPrompt,
      delaySeconds: delay.inSeconds.clamp(5, 86400 * 7),
    );
  }

  Future<void> cancelAllAutomations() async {
    try {
      await _channel.invokeMethod('cancelScheduledGoals');
    } catch (_) {}
  }
}
