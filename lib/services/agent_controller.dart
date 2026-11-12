import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../actions/action_dispatcher.dart';
import '../models/agent_action.dart';
import '../models/agent_step.dart';
import '../models/saved_scenario.dart';
import '../models/task_history.dart';
import 'accessibility_bridge.dart';
import 'ai_service.dart';
import 'history_service.dart';
import 'scenario_service.dart';
import 'settings_service.dart';
import 'system_actions_service.dart';
import 'voice_service.dart';

typedef ConfirmDangerousActionCallback = Future<bool> Function(AgentAction action);

class AgentController extends ChangeNotifier {
  static final AgentController instance = AgentController._();
  AgentController._() {
    _bindNativeEmergencyStop();
    AccessibilityBridge.onMicRequested = _handleMicRequested;
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
  String statusBanner = 'Готов к работе (План + Самопроверка + Сценарии + Веб-ИИ)';
  List<String> currentPlan = [];
  SavedScenario? activeReplayingScenario;
  final List<AgentStep> liveSteps = [];
  final List<String> _userMessages = [];

  void addUserMessage(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _userMessages.add(t);
    statusBanner = '💬 Вы: $t';
    notifyListeners();
  }

  Future<void> _handleMicRequested() async {
    await VoiceService.instance.startListening(
      onResult: (_) {},
      onFinal: (t) {
        if (isRunning) {
          addUserMessage(t);
        } else {
          runAgent(t);
        }
      },
    );
  }

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

  String _screenFingerprint(String tree, String pkg) {
    final lines = tree.split('\n').take(35).join('|');
    return '$pkg::${lines.hashCode}';
  }

  Future<void> runAgent(String goal) async {
    if (isRunning || goal.trim().isEmpty) return;

    final settings = SettingsService.instance;
    final historyService = HistoryService.instance;
    final scenarioService = ScenarioService.instance;

    if (historyService.todayTaskCount >= settings.maxDailyTasks) {
      statusBanner = 'Превышен дневной лимит задач (${settings.maxDailyTasks})';
      notifyListeners();
      return;
    }

    isRunning = true;
    _stopRequested = false;
    currentGoal = goal.trim();
    currentStepIndex = 0;
    currentPlan = [];
    liveSteps.clear();
    _userMessages.clear();

    // Проверяем, есть ли уже сохранённый сценарий для этой задачи
    activeReplayingScenario = settings.useSavedScenarios
        ? scenarioService.findMatchingScenario(currentGoal)
        : null;
    if (activeReplayingScenario != null && activeReplayingScenario!.planSteps.isNotEmpty) {
      currentPlan = List<String>.from(activeReplayingScenario!.planSteps);
      statusBanner = '⚡ Найден сохранённый сценарий: "${activeReplayingScenario!.title}"';
    } else {
      statusBanner = '🚀 Запуск задачи и построение плана: $currentGoal';
    }
    notifyListeners();

    final startTime = DateTime.now();
    final maxSteps = settings.maxSteps;
    final maxMinutes = settings.maxMinutes;
    bool isSuccess = true;
    int guardRejects = 0;
    int unverifiedStreak = 0;
    String selfCheckWarning = '';
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
      String elementsBefore = await bridge.getScreenTree();
      for (int i = 0; i < 3 && elementsBefore.trim().isEmpty && !_stopRequested; i++) {
        await Future.delayed(const Duration(milliseconds: 600));
        elementsBefore = await bridge.getScreenTree();
      }
      final fpBefore = _screenFingerprint(elementsBefore, activePkg);

      AgentAction action;
      String expectedChange = '';

      // Если активен сохранённый сценарий и экран меняется штатно — берём шаг из сценария без вызова модели!
      if (activeReplayingScenario != null &&
          step < activeReplayingScenario!.actions.length &&
          unverifiedStreak == 0 &&
          _userMessages.isEmpty) {
        action = activeReplayingScenario!.actions[step];
        expectedChange = 'Шаг ${step + 1} из сохранённого сценария';
        statusBanner =
            '⚡ Сценарий [${step + 1}/${activeReplayingScenario!.actions.length}]: ${action.humanReadableSummary}';
        notifyListeners();
      } else {
        statusBanner =
            'Шаг $currentStepIndex из $maxSteps: 🧠 План и решение (${settings.selectedModel})...';
        notifyListeners();

        final decision = await aiService.nextAction(
          goal: currentGoal,
          screenTree: elementsBefore,
          activePackage: activePkg,
          history: List.unmodifiable(liveSteps),
          currentPlan: currentPlan,
          selfCheckWarning: selfCheckWarning,
          memoryContext: memoryContext,
          userMessages: _userMessages
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n'),
        );

        if (decision.plan.isNotEmpty) {
          currentPlan = decision.plan;
        }
        expectedChange = decision.expectedScreenChange;
        action = decision.action;
      }

      if (_stopRequested) {
        isSuccess = false;
        finishReason = 'Остановлено пользователем';
        break;
      }

      final goalLower = currentGoal.toLowerCase();
      final writeIntent =
          RegExp(r'пиши|напиши|написать|отправь|сообщен|скажи|заметк').hasMatch(goalLower);
      final explicitCall =
          RegExp(r'(^|\s)(позвони|набери|вызови|звонок|запиши.*врач|барбершоп)').hasMatch(goalLower);
      String? guardMsg;
      if ((action.type == 'call' || action.type == 'call_contact') &&
          writeIntent &&
          !explicitCall) {
        guardMsg =
            'Заблокировано: пользователь просил написать сообщение, а не звонить. Работай через экран мессенджера.';
      } else if (action.type == 'finish' &&
          writeIntent &&
          guardRejects < 2 &&
          !liveSteps.any((s) =>
              s.action.type == 'input_text' ||
              s.action.type == 'send_messenger' ||
              s.action.type == 'send_sms' ||
              s.action.type == 'reply_notification')) {
        guardMsg =
            'Самопроверка отклонила finish: текст сообщения ещё не был введён или отправлен.';
      }
      if (guardMsg != null) {
        guardRejects++;
        selfCheckWarning = '⚠️ $guardMsg';
        liveSteps.add(
          AgentStep(
            index: step,
            action: action,
            timestamp: DateTime.now(),
            executionResult: guardMsg,
            verified: false,
            verificationNote: guardMsg,
          ),
        );
        statusBanner = '⛔ $guardMsg';
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
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

      statusBanner =
          'Шаг $currentStepIndex из $maxSteps: ${action.iconEmoji} ${action.humanReadableSummary}';
      notifyListeners();

      final execResult = await actionDispatcher.dispatch(action);

      // Ждём реакции интерфейса и проводим САМОПРОВЕРКУ (изменился ли экран)
      await Future.delayed(Duration(
        milliseconds: action.type == 'open_app'
            ? 2000
            : (action.type == 'tap' || action.type == 'input_text' || action.type == 'scroll')
                ? 1000
                : 500,
      ));

      final pkgAfter = await bridge.getActivePackageName();
      final elementsAfter = await bridge.getScreenTree();
      final fpAfter = _screenFingerprint(elementsAfter, pkgAfter);

      const uiMutatingTypes = {
        'tap',
        'tap_xy',
        'input_text',
        'scroll',
        'swipe',
        'open_app',
        'navigate_back',
      };
      bool stepVerified = true;
      String verifyNote = expectedChange.isNotEmpty
          ? 'Ожидалось: $expectedChange — Выполнено'
          : 'Проверено: OK';

      if (settings.selfVerificationEnabled &&
          uiMutatingTypes.contains(action.type) &&
          elementsBefore.isNotEmpty &&
          fpBefore == fpAfter) {
        stepVerified = false;
        unverifiedStreak++;
        verifyNote = 'Экран не изменился после действия (${action.type}). Переключаюсь на обходной путь.';
        selfCheckWarning =
            '⚠️ САМОПРОВЕРКА: После шага ${step + 1} (${action.humanReadableSummary}) экран НЕ изменился! Выбери другой элемент, сделай scroll или используй другой инструмент.';
        // Отключаем автопроигрывание сценария и передаём управление ИИ
        activeReplayingScenario = null;
      } else {
        unverifiedStreak = 0;
        selfCheckWarning = '';
      }

      final enrichedResult = execResult.length > 500
          ? '${execResult.substring(0, 500)}...'
          : execResult;

      final stepRecord = AgentStep(
        index: step,
        action: action,
        timestamp: DateTime.now(),
        screenSummary: elementsAfter.length > 300
            ? '${elementsAfter.substring(0, 300)}...'
            : elementsAfter,
        executionResult: enrichedResult,
        verified: stepVerified,
        verificationNote: verifyNote,
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

      // Если сценарий дошёл до конца всех записанных шагов — завершаем успешно
      if (activeReplayingScenario != null &&
          step + 1 >= activeReplayingScenario!.actions.length) {
        finishReason = 'Выполнено по сохранённому сценарию «${activeReplayingScenario!.title}»';
        break;
      }

      const singleShotSystemActions = {
        'set_alarm',
        'set_timer',
        'toggle_flashlight',
        'send_sms',
        'call',
        'call_contact',
        'ai_voice_call',
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
            verified: true,
            verificationNote: 'Системное действие подтверждено',
          ),
        );
        break;
      }
    }

    isRunning = false;
    activeReplayingScenario = null;
    statusBanner = isSuccess
        ? '✅ Готово за ${liveSteps.length} шаг(ов): $finishReason'
        : '⚠️ $finishReason';
    notifyListeners();

    // Если задача прошла успешно — автоматически запоминаем сценарий!
    if (isSuccess && liveSteps.isNotEmpty) {
      await scenarioService.recordSuccessfulRun(
        goal: currentGoal,
        steps: liveSteps,
        plan: currentPlan,
      );
    }

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
        plan: List<String>.from(currentPlan),
        startedAt: startTime,
        finishedAt: DateTime.now(),
        isSuccess: isSuccess,
        finalStatus: finishReason,
      ),
    );
  }
}
