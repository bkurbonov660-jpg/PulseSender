import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_action.dart';
import '../models/agent_step.dart';
import 'settings_service.dart';

class AiDecision {
  final String thought;
  final AgentAction action;
  final String rawResponse;

  const AiDecision({
    required this.thought,
    required this.action,
    required this.rawResponse,
  });
}

class AiService {
  static final AiService instance = AiService._();
  factory AiService() => instance;
  AiService._();

  static const String _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  static const String _systemPrompt = '''
Ты — ИИ-агент управления Android-телефоном по имени PulseAgent.
Тебе дают:
1. ЦЕЛЬ пользователя (на русском языке)
2. ТЕКУЩИЙ ЭКРАН (список UI-элементов с индексами и координатами)
3. ИСТОРИЮ твоих прошлых шагов и КОНТЕКСТ ПАМЯТИ

Твоя задача — вернуть СТРОГО ОДИН JSON-объект со следующим действием (без пояснений вокруг JSON):

{
  "thought": "краткое рассуждение на русском (1 предложение)",
  "action": {
    "type": "<тип действия>",
    ...параметры...
  }
}

Доступные типы действий:

ЭКРАННЫЕ (Accessibility):
• {"type": "tap", "target": 3}
• {"type": "tap_xy", "x": 540, "y": 1200}
• {"type": "input_text", "target": 2, "text": "привет"}
• {"type": "scroll", "direction": "down"} // up|down|left|right
• {"type": "swipe", "x1": 500, "y1": 1500, "x2": 500, "y2": 300}
• {"type": "long_press", "target": 4}
• {"type": "navigate_back"} | {"type": "navigate_home"} | {"type": "navigate_recents"} | {"type": "navigate_notifications"}
• {"type": "open_app", "package": "com.whatsapp", "app_name": "WhatsApp"}
• {"type": "wait", "seconds": 3}
• {"type": "wait_for", "text": "Загрузка завершена", "timeout": 10}

СИСТЕМНЫЕ (прямые, без кликов по UI — используй их ПРИОРИТЕТНО!):
• {"type": "set_alarm", "hour": 7, "minute": 30, "label": "Подъём", "days": [1,2,3,4,5], "vibrate": true}
• {"type": "dismiss_alarm"}
• {"type": "show_alarms"}
• {"type": "set_timer", "seconds": 300, "label": "Чай"}
• {"type": "open_stopwatch"}
• {"type": "call", "number": "+992900000000"} или {"type": "call_contact", "name": "Мама"}
• {"type": "end_call"}
• {"type": "open_call_log"}
• {"type": "send_sms", "number": "+992900000000", "text": "Привет!"}
• {"type": "read_sms", "limit": 5}
• {"type": "create_reminder", "title": "Встреча", "datetime": "2026-04-20T15:00:00", "minutes_before": 15}
• {"type": "create_calendar_event", "title": "Врач", "start": "2026-04-21T10:00:00", "end": "2026-04-21T11:00:00", "location": "Клиника"}
• {"type": "get_calendar_events", "days": 7}
• {"type": "find_contact", "name": "Али"}
• {"type": "create_contact", "name": "Али", "phone": "+992900111222"}
• {"type": "read_notifications"}
• {"type": "dismiss_notifications"}
• {"type": "set_volume", "stream": "music", "level": 50} // stream: music|ring|alarm|notification, level: 0-100
• {"type": "set_brightness", "level": 80} // 0-100
• {"type": "toggle_wifi", "state": true}
• {"type": "toggle_bluetooth", "state": true}
• {"type": "toggle_airplane"}
• {"type": "toggle_dnd", "state": true}
• {"type": "toggle_flashlight", "state": true}
• {"type": "vibrate", "ms": 500}
• {"type": "open_power_saver"}
• {"type": "take_screenshot"}
• {"type": "open_camera", "mode": "photo"} // photo|video
• {"type": "record_audio", "seconds": 10}
• {"type": "open_gallery"}
• {"type": "play_media", "state": "play"} // play|pause|next|previous
• {"type": "open_music_track", "query": "Imagine Dragons", "app": "spotify"}
• {"type": "check_network"}
• {"type": "get_battery"}
• {"type": "get_location"}
• {"type": "open_map", "address": "Душанбе проспект Рудаки"}
• {"type": "call_taxi", "address": "Аэропорт"}
• {"type": "list_apps"}
• {"type": "open_play_store", "package": "org.telegram.messenger"}
• {"type": "uninstall_app", "package": "com.example.app"}
• {"type": "open_url", "url": "https://google.com"}
• {"type": "search_web", "query": "погода в Душанбе"}
• {"type": "download_file", "url": "https://example.com/file.pdf", "filename": "file.pdf"}
• {"type": "send_email", "to": "test@mail.com", "subject": "Тема", "body": "Текст письма"}
• {"type": "send_messenger", "app": "telegram", "phone": "+992900000000", "text": "Привет"}
• {"type": "smart_home", "deeplink": "", "package": "com.google.android.apps.chromecast.app"}

ЗАВЕРШЕНИЕ:
• {"type": "finish", "reason": "Будильник установлен на 7:30"}
• {"type": "fail", "reason": "Контакт не найден"}
• {"type": "ask_user", "question": "Уточните, на какое время поставить будильник?"}
• {"type": "say", "text": "Ответ пользователю голосом и в логе (задача продолжается)"}

ПРАВИЛА:
1. Системное действие (set_alarm, set_timer, toggle_flashlight, set_volume и т.п.) используй ТОЛЬКО когда оно ровно то, что просит пользователь.
2. ЗАПРЕЩЕНО звонить (call, call_contact), если пользователь не сказал слово «позвони/набери/вызови». Фразы «напиши», «отправь сообщение», «скажи ему», «в Макс / WhatsApp / Telegram» означают ПЕРЕПИСКУ ЧЕРЕЗ ЭКРАН мессенджера — никогда не звонок.
3. Если экран пуст или приложение ещё грузится — верни {"type": "wait", "seconds": 2} и смотри экран снова. Не завершай задачу и не переходи к системным действиям из-за пустого экрана.
4. СЦЕНАРИЙ «написать сообщение в мессенджере» (MAX/Макс, Telegram, WhatsApp, VK и др.): open_app -> wait -> найди поиск (лупа / «Поиск») или список чатов -> tap -> input_text с именем контакта в поле поиска -> tap по найденному контакту (чат откроется) -> input_text в поле «Сообщение» (EditText) ПОЛНЫЙ текст -> tap по кнопке отправки (стрелка / «Отправить») -> следующим шагом проверь экран: сообщение появилось в чате -> finish. Контакт не найден — scroll и ищи дальше, потом ask_user.
5. СЦЕНАРИЙ «заметки»: open_app (Заметки / Notes) -> tap «+» / «Создать» / «Новая заметка» -> input_text в заголовок (если есть отдельное поле) -> input_text в основное поле всё содержимое -> убедись, что текст виден на экране -> finish. Не завершай задачу, пока текст не введён.
6. Если пользователь просит «напиши всё, что умеешь» — сам составь полный текст со списком своих возможностей (управление экраном, звонки, SMS, мессенджеры, будильники, таймеры, календарь, напоминания, громкость, яркость, Wi-Fi, Bluetooth, фонарик, камера, музыка, карты, такси, заметки, скриншоты, уведомления, голосовой ввод) и введи его целиком одним input_text.
7. Текст, который пользователь продиктовал для отправки, не переписывай и не меняй смысл.
8. Для input_text выбирай target у элемента EditText из ТЕКУЩЕГО списка. После ввода проверяй экран.
9. Если в блоке «СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЯ ВО ВРЕМЯ РАБОТЫ» есть реплики — это уточнения или вопросы владельца. Учти их. На вопрос ответь через {"type": "say", "text": "..."} и продолжай задачу.
10. Не повторяй одно и то же действие больше 2 раз подряд: смени путь или задай ask_user.
11. Отвечай ТОЛЬКО валидным JSON без markdown-блоков.
''';

  Future<(bool ok, String message)> verifyApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return (false, 'Ключ пуст. Вставьте ваш ключ sk-or-v1-...');
    }
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $trimmed',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/bkurbonov660-jpg/PulseSender',
              'X-Title': 'PulseAgent',
            },
            body: jsonEncode({
              'model': SettingsService.instance.selectedModel,
              'messages': [
                {'role': 'user', 'content': 'Ответь одним словом OK'}
              ],
              'max_tokens': 8,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return (true, 'Ключ подтверждён! OpenRouter ответил успешно (200 OK).');
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        return (false, 'OpenRouter отклонил ключ (HTTP ${resp.statusCode}). Проверьте правильность ключа.');
      } else {
        return (true, 'Ключ сохранён (статус модели: HTTP ${resp.statusCode}).');
      }
    } catch (e) {
      if (trimmed.startsWith('sk-or-')) {
        return (true, 'Ключ сохранён локально (проверка сети: $e).');
      }
      return (false, 'Ошибка соединения: $e');
    }
  }

  Future<AgentAction> decide({
    required String goal,
    required String screenElements,
    required List<AgentStep> previousSteps,
    required String memoryContext,
    String activePackage = '',
    String userMessages = '',
  }) async {
    final decision = await nextAction(
      goal: goal,
      screenTree: screenElements,
      activePackage: activePackage,
      history: previousSteps,
      memoryContext: memoryContext,
      userMessages: userMessages,
    );
    return decision.action;
  }

  Future<AiDecision> nextAction({
    required String goal,
    required String screenTree,
    required String activePackage,
    required List<AgentStep> history,
    required String memoryContext,
    String userMessages = '',
  }) async {
    final settings = SettingsService.instance;
    final apiKey = settings.effectiveApiKey;
    if (apiKey.isEmpty) {
      return const AiDecision(
        thought: 'Не указан API-ключ OpenRouter.',
        action: AgentAction(
          type: 'fail',
          params: {
            'reason': 'Сначала введите и подтвердите ваш API-ключ OpenRouter в карточке «API-ключ OpenRouter» на экране Агента или в Настройках.',
          },
        ),
        rawResponse: '{}',
      );
    }

    final modelsToTry = <String>[
      settings.selectedModel,
      ...SettingsService.availableModels.where((m) => m != settings.selectedModel),
    ];

    final historySummary = history.isEmpty
        ? 'Шагов ещё не было (это Шаг 1).'
        : history
            .map((s) =>
                'Шаг ${s.stepNumber}: действие=${jsonEncode(s.action.toJson())} -> результат="${s.executionResult}"')
            .join('\n');

    final userPrompt = '''
ЦЕЛЬ ПОЛЬЗОВАТЕЛЯ: $goal

КОНТЕКСТ ПАМЯТИ ПРОШЛЫХ ЗАДАЧ:
${memoryContext.isEmpty ? 'Нет записей' : memoryContext}

АКТИВНЫЙ ПАКЕТ НА ЭКРАНЕ: ${activePackage.isEmpty ? 'неизвестно' : activePackage}

ТЕКУЩЕЕ ДЕРЕВО UI ЭКРАНА:
${screenTree.isEmpty ? '[Экран пока пуст: приложение грузится или AccessibilityService не включён. Сделай wait 2 секунды и смотри снова. НЕ звони и НЕ завершай задачу.]' : screenTree}

СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЯ ВО ВРЕМЯ РАБОТЫ:
${userMessages.isEmpty ? 'нет' : userMessages}

ИСТОРИЯ ВЫПОЛНЕННЫХ ШАГОВ В ТЕКУЩЕЙ ЗАДАЧЕ:
$historySummary

Верни JSON следующего шага (если цель уже выполнена в предыдущем шаге — верни {"thought": "Задача выполнена", "action": {"type": "finish", "reason": "..."}}):
''';

    String lastError = 'Неизвестная ошибка сети';

    for (int attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
    bool networkDown = false;
    for (final model in modelsToTry) {
      try {
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://github.com/bkurbonov660-jpg/PulseSender',
                'X-Title': 'PulseAgent',
              },
              body: jsonEncode({
                'model': model,
                'temperature': 0.1,
                'messages': [
                  {'role': 'system', 'content': _systemPrompt},
                  {'role': 'user', 'content': userPrompt},
                ],
              }),
            )
            .timeout(const Duration(seconds: 35));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final choices = decoded['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices.first['message'] as Map<String, dynamic>?;
            final content = (msg?['content'] ?? '').toString().trim();
            if (content.isNotEmpty) {
              return _parseDecision(content);
            }
          }
        } else {
          lastError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastError = e.toString();
        final es = e.toString();
        if (es.contains('SocketException') || es.contains('TimeoutException') || es.contains('Failed host lookup')) {
          networkDown = true;
        }
      }
      if (networkDown) break;
    }
    }

    return AiDecision(
      thought: 'Ошибка обращения к OpenRouter: $lastError',
      action: AgentAction(
        type: 'fail',
        params: {
          'reason': lastError.contains('Failed host lookup')
              ? 'Нет связи с openrouter.ai (DNS не находит адрес). Проверьте интернет, включите VPN или смените Частный DNS на 8.8.8.8 и повторите. Детали: $lastError'
              : 'Не удалось получить ответ от моделей OpenRouter: $lastError',
        },
      ),
      rawResponse: lastError,
    );
  }

  AiDecision _parseDecision(String rawContent) {
    var cleaned = rawContent.trim();
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      final jsonSlice = cleaned.substring(start, end + 1);
      try {
        final map = jsonDecode(jsonSlice) as Map<String, dynamic>;
        final thought = (map['thought'] ?? 'Выполняю шаг').toString();
        final actionObj = map['action'];
        if (actionObj is Map) {
          return AiDecision(
            thought: thought,
            action: AgentAction.fromJson(Map<String, dynamic>.from(actionObj)),
            rawResponse: jsonSlice,
          );
        }
        return AiDecision(
          thought: thought,
          action: AgentAction.fromJson(map),
          rawResponse: jsonSlice,
        );
      } catch (_) {}
    }

    return AiDecision(
      thought: 'Ответ модели получен',
      action: AgentAction(
        type: 'finish',
        params: {'reason': cleaned},
      ),
      rawResponse: rawContent,
    );
  }
}
