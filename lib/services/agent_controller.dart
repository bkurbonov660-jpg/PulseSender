import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../actions/action_dispatcher.dart';
import '../models/agent_action.dart';
import '../models/agent_step.dart';
import '../models/task_history.dart';
import 'accessibility_bridge.dart';
import 'ai_service.dart';
import 'history_service.dart';
import 'settings_service.dart';
import 'system_actions_service.dart';
import 'voice_service.dart';

typedef ConfirmDangerousActionCallback = Future<bool> Function(AgentAction action);

class AgentController extends ChangeNotifier {
  static final AgentController instance = AgentController._();
  AgentController._() {
    _bindNativeEmergencyStop();
  }

  final AccessibilityBridge bridge = AccessibilityBridge();
  final SystemActionsService systemActions = SystemActionsService();
  final AiService aiService = AiService.instance;
  late final AgentActionDispatcher actionDispatcher = AgentActionDispatcher(
    accessibilityBridge: bridge,
    systemActions: systemActions,
  );

  bool isRunning = false;
  bool _stopRequested = false;
  String currentGoal = '';
  int currentStepIndex = 0;
  String statusBanner = 'Готов к работе';
  final List<AgentStep> liveSteps = [];

  ConfirmDangerousActionCallback? onConfirmDangerousAction;

  void _bindNativeEmergencyStop() {
    bridge.registerNativeCallbacks(
      onEmergencyStop: (reason) {
        emergencyStop(reason: reason);
      },
      onScheduledGoalTriggered: (goal) {
        if (goal.isNotEmpty && !isRunning) {
          runAgent(goal);
        }
      },
    );
  }

  void emergencyStop({String reason = 'Остановлено пользователем'}) {
    if (!isRunning) return;
    _stopRequested = true;
    statusBanner = '🛑 $reason';
    VoiceService.instance.speak('Агент остановлен');
    notifyListeners();
  }

  Future<void> runAgent(String goal) async {
    if (isRunning || goal.trim().isEmpty) return;

    final settings = SettingsService.instance;
    final historyService = HistoryService.instance;

    if (historyService.todayTaskCount >= settings.maxDailyTasks) {
      statusBanner = 'Превышен дневной лимит задач (${settings.maxDailyTasks})';
      notifyListeners();
      return;
    }

    isRunning = true;
    _stopRequested = false;
    currentGoal = goal.trim();
    currentStepIndex = 0;
    liveSteps.clear();
    statusBanner = 'Запуск задачи: $currentGoal';
    notifyListeners();

    final startTime = DateTime.now();
    final maxSteps = settings.maxSteps;
    final maxMinutes = settings.maxMinutes;
    bool isSuccess = true;
    String finishReason = 'Задача выполнена';

    final memoryContext = historyService.buildMemoryContext(currentGoal);

    for (int step = 0; step < maxSteps; step++) {
      if (_stopRequested) {
        isSuccess = false;
        finishReason = 'Экстренная остановка';
        break;
      }

      currentStepIndex = step + 1;

      if (DateTime.now().difference(startTime).inMinutes >= maxMinutes) {
        isSuccess = false;
        finishReason = 'Таймаут ($maxMinutes мин.)';
        break;
      }

      final activePkg = await bridge.getActivePackageName();
      if (activePkg.isNotEmpty && settings.blacklistedPackages.contains(activePkg)) {
        await bridge.performGlobalNav('home');
        isSuccess = false;
        finishReason = 'Заблокировано политикой безопасности: банковское приложение ($activePkg)';
        break;
      }

      statusBanner = 'Шаг $currentStepIndex из $maxSteps: 👁 Читаю экран...';
      notifyListeners();
      final elements = await bridge.getScreenTree();

      statusBanner = 'Шаг $currentStepIndex из $maxSteps: 🧠 Думаю через ${settings.selectedModel}...';
      notifyListeners();

      final action = await aiService.decide(
        goal: currentGoal,
        screenElements: elements,
        previousSteps: List.unmodifiable(liveSteps),
        memoryContext: memoryContext,
        activePackage: activePkg,
      );

      if (_stopRequested) {
        isSuccess = false;
        finishReason = 'Остановлено пользователем';
        break;
      }

      final hourNow = DateTime.now().hour;
      if (action.type == 'open_camera' &&
          settings.blockCameraAtNight &&
          (hourNow >= 23 || hourNow < 6)) {
        isSuccess = false;
        finishReason = 'Заблокировано: не открывать камеру ночью';
        break;
      }

      if (action.isDangerous &&
          settings.confirmDangerousActions &&
          !settings.alwaysAllowedActions.contains(action.type)) {
        if (onConfirmDangerousAction != null) {
          final allowed = await onConfirmDangerousAction!(action);
          if (!allowed) {
            isSuccess = false;
            finishReason = 'Отклонено пользователем: ${action.humanReadableSummary}';
            break;
          }
        }
      }

      await systemActions.updateAgentProgressNotification(
        title: 'PulseAgent выполняет задачу',
        body: 'Шаг $currentStepIndex из $maxSteps: ${action.humanReadableSummary}',
        step: currentStepIndex,
        maxSteps: maxSteps,
        ongoing: true,
      );

      statusBanner = 'Шаг $currentStepIndex из $maxSteps: ${action.iconEmoji} ${action.humanReadableSummary}';
      notifyListeners();

      final execResult = await actionDispatcher.dispatch(action);

      final stepRecord = AgentStep(
        index: step,
        action: action,
        timestamp: DateTime.now(),
        screenSummary: elements.length > 300 ? '${elements.substring(0, 300)}...' : elements,
        executionResult: execResult,
      );
      liveSteps.add(stepRecord);
      notifyListeners();

      if (action.type == 'finish') {
        finishReason = action.reason ?? execResult;
        break;
      }

      if (action.type == 'fail' || action.type == 'ask_user') {
        isSuccess = action.type != 'fail';
        finishReason = action.reason ?? execResult;
        break;
      }

      const singleShotSystemActions = {
        'set_alarm',
        'set_timer',
        'toggle_flashlight',
        'send_sms',
        'call',
        'call_contact',
        'create_reminder',
        'create_calendar_event',
      };
      if (singleShotSystemActions.contains(action.type)) {
        finishReason = execResult;
        liveSteps.add(
          AgentStep(
            index: step + 1,
            action: AgentAction(type: 'finish', params: {'reason': execResult}),
            timestamp: DateTime.now(),
            executionResult: 'Готово',
          ),
        );
        break;
      }

      await Future.delayed(const Duration(milliseconds: 800));
    }

    isRunning = false;
    statusBanner = isSuccess
        ? '✅ Готово за ${liveSteps.length} шаг(ов): $finishReason'
        : '⚠️ $finishReason';
    notifyListeners();

    await systemActions.updateAgentProgressNotification(
      title: isSuccess ? 'Задача выполнена' : 'Задача остановлена',
      body: '$finishReason (шагов: ${liveSteps.length})',
      step: liveSteps.length,
      maxSteps: maxSteps,
      ongoing: false,
    );

    await VoiceService.instance.speak(
      isSuccess ? 'Задача выполнена. $finishReason' : 'Не удалось выполнить. $finishReason',
    );

    await historyService.save(
      TaskHistory(
        id: const Uuid().v4(),
        goal: currentGoal,
        steps: List<AgentStep>.from(liveSteps),
        startedAt: startTime,
        finishedAt: DateTime.now(),
        isSuccess: isSuccess,
        finalStatus: finishReason,
      ),
    );
  }
}
