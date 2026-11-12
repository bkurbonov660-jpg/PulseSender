import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_action.dart';
import '../models/agent_step.dart';
import 'settings_service.dart';

class AiDecision {
  final String thought;
  final List<String> plan;
  final String expectedScreenChange;
  final AgentAction action;
  final String rawResponse;

  const AiDecision({
    required this.thought,
    this.plan = const [],
    this.expectedScreenChange = '',
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
Ты — автономный ИИ-агент PulseAgent v2.0 с функцией ПЛАНИРОВАНИЯ, САМОПРОВЕРКИ, СВОБОДНОГО ДОСТУПА В ИНТЕРНЕТ и ЗАПИСИ НА УСЛУГИ.
Тебе дают:
1. ЦЕЛЬ пользователя
2. ТЕКУЩИЙ ПЛАН (если уже составлен) и предупреждения САМОПРОВЕРКИ (если прошлый шаг не изменил экран!)
3. ТЕКУЩИЙ ЭКРАН (список UI-элементов с индексами и координатами)
4. ИСТОРИЮ шагов и КОНТЕКСТ ПАМЯТИ / СОХРАНЁННЫХ СЦЕНАРИЕВ

Твоя задача — вернуть СТРОГО ОДИН JSON-объект со следующим действием:

{
  "thought": "краткое рассуждение и проверка прошлого шага",
  "plan": [
    "1. Первый шаг плана",
    "2. Второй шаг плана",
    "3. Третий шаг и проверка результата"
  ],
  "expected_change": "что должно появиться или измениться на экране после этого действия",
  "action": {
    "type": "<тип действия>",
    ...параметры...
  }
}

Доступные типы действий:

СВОБОДНЫЙ ИНТЕРНЕТ, СРАВНЕНИЕ ЦЕН И ЗАПИСЬ НА УСЛУГИ (РАБОТАЮТ НАПРЯМУЮ БЕЗ БРАУЗЕРА!):
• {"type": "web_research", "query": "лучшие барбершопы Душанбе цены"} — свободный поиск информации в интернете
• {"type": "compare_prices", "item": "стрижка в барбершопе / приём терапевта / смартфон"} — поиск и сравнение самых дешёвых вариантов в интернете
• {"type": "fetch_webpage", "url": "https://example.com"} — прочитать любую страницу целиком
• {"type": "book_service", "service": "стрижка / врач терапевт", "place": "Барбершоп / Клиника", "time": "завтра в 15:00", "phone": ""} — комплексная запись на услугу
• {"type": "ai_voice_call", "number": "+992900000000", "service": "запись в барбершоп на завтра в 15:00", "time": "15:00"} — позвонить с телефона и поговорить голосом ИИ для записи!
• {"type": "reply_notification", "key": "<ключ уведомления>", "sender": "Имя", "text": "Буду через 10 минут"} — мгновенный ответ на сообщение

ЭКРАННЫЕ (Accessibility):
• {"type": "tap", "target": 3}
• {"type": "tap_xy", "x": 540, "y": 1200}
• {"type": "input_text", "target": 2, "text": "привет"}
• {"type": "scroll", "direction": "down"} // up|down|left|right
• {"type": "swipe", "x1": 500, "y1": 1500, "x2": 500, "y2": 300}
• {"type": "long_press", "target": 4}
• {"type": "navigate_back"} | {"type": "navigate_home"} | {"type": "navigate_recents"} | {"type": "navigate_notifications"}
• {"type": "open_app", "package": "com.whatsapp", "app_name": "WhatsApp"}
• {"type": "wait", "seconds": 2}
• {"type": "wait_for", "text": "Загрузка", "timeout": 10}

СИСТЕМНЫЕ:
• {"type": "set_alarm", "hour": 7, "minute": 30, "label": "Подъём", "days": [1,2,3,4,5], "vibrate": true}
• {"type": "set_timer", "seconds": 300, "label": "Чай"}
• {"type": "call", "number": "+992900000000"} или {"type": "call_contact", "name": "Мама"}
• {"type": "answer_call"} | {"type": "end_call"}
• {"type": "send_sms", "number": "+992900000000", "text": "Привет!"}
• {"type": "read_sms", "limit": 5}
• {"type": "create_reminder", "title": "Встреча", "datetime": "2026-04-20T15:00:00"}
• {"type": "create_calendar_event", "title": "Врач", "start": "2026-04-21T10:00:00", "end": "2026-04-21T11:00:00"}
• {"type": "read_notifications"} | {"type": "dismiss_notifications"}
• {"type": "set_volume", "stream": "music", "level": 50}
• {"type": "set_brightness", "level": 80}
• {"type": "toggle_flashlight", "state": true}
• {"type": "open_map", "address": "Душанбе проспект Рудаки"}
• {"type": "call_taxi", "address": "Аэропорт"}
• {"type": "list_apps"}

ЗАВЕРШЕНИЕ:
• {"type": "finish", "reason": "Подробный отчёт о выполненной задаче, найденных ценах или записи"}
• {"type": "fail", "reason": "Причина"}
• {"type": "ask_user", "question": "Вопрос пользователю"}
• {"type": "say", "text": "Озвучить голосом промежуточный отчёт"}

ПРАВИЛА АВТОНОМНОСТИ И САМОПРОВЕРКИ:
1. На Шаге 1 ВСЕГДА заполняй массив "plan" из 3–5 конкретных шагов.
2. После каждого действия проверяй: изменился ли экран как надо? Если в промпте указано «⚠️ САМОПРОВЕРКА: Экран НЕ изменился после прошлого действия», НЕ ПОВТОРЯЙ тот же tap! Попробуй другой элемент, tap_xy по координатам, scroll, или используй прямой инструмент (web_research, compare_prices, book_service).
3. Если нужно найти самые дешёвые цены, изучить отзывы или записаться на услугу — сначала вызови compare_prices или web_research, изучи результаты, а затем запиши клиента через приложение или ai_voice_call.
4. Отвечай ТОЛЬКО валидным JSON без markdown-обёрток.
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

  /// Генерация умного ответа на входящее сообщение
  Future<String> generateQuickReply({
    required String sender,
    required String incomingText,
    required String appPackage,
  }) async {
    final apiKey = SettingsService.instance.effectiveApiKey;
    if (apiKey.isEmpty) return 'Буду через 10 минут, скоро отвечу!';
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/bkurbonov660-jpg/PulseSender',
              'X-Title': 'PulseAgent',
            },
            body: jsonEncode({
              'model': SettingsService.instance.selectedModel,
              'temperature': 0.2,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Ты — личный ИИ-помощник. Пришло сообщение от "$sender" в $appPackage. Предложи короткий, естественный и вежливый ответ от первого лица (1 предложение, без кавычек). Если спрашивают когда буду или где я — ответь "Буду через 10 минут!".'
                },
                {'role': 'user', 'content': incomingText},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final content =
            (decoded['choices']?[0]?['message']?['content'] ?? '').toString().trim();
        if (content.isNotEmpty) {
          return content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
        }
      }
    } catch (_) {}
    return 'Буду через 10 минут!';
  }

  /// Краткая сводка разговора со спамером или незнакомым номером
  Future<String> summarizeScreenedCall({
    required String phoneNumber,
    required String transcript,
  }) async {
    final apiKey = SettingsService.instance.effectiveApiKey;
    if (apiKey.isEmpty) return 'Звонил $phoneNumber: "$transcript"';
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/bkurbonov660-jpg/PulseSender',
              'X-Title': 'PulseAgent',
            },
            body: jsonEncode({
              'model': SettingsService.instance.selectedModel,
              'temperature': 0.1,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Ты — телефонный ИИ-секретарь. Проанализируй ответ звонящего на вопрос "Кто это и по какому вопросу?". Напиши в 2 строках: 1) Кто звонил и зачем. 2) Вердикт (СПАМ / ВАЖНО / ДОСТАВКА / КЛИЕНТ).'
                },
                {
                  'role': 'user',
                  'content': 'Номер: $phoneNumber. Ответ абонента: "$transcript"'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final content =
            (decoded['choices']?[0]?['message']?['content'] ?? '').toString().trim();
        if (content.isNotEmpty) {
          return content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
        }
      }
    } catch (_) {}
    return 'Номер $phoneNumber сообщил: "$transcript"';
  }

  Future<AiDecision> nextAction({
    required String goal,
    required String screenTree,
    required String activePackage,
    required List<AgentStep> history,
    required List<String> currentPlan,
    required String selfCheckWarning,
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
            'reason':
                'Сначала введите и подтвердите ваш API-ключ OpenRouter в карточке «API-ключ OpenRouter» на экране Агента или в Настройках.',
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
        ? 'Шагов ещё не было (это Шаг 1 — составь план из 3-5 шагов и выбери первое действие).'
        : history
            .map((s) =>
                'Шаг ${s.stepNumber}: действие=${jsonEncode(s.action.toJson())} -> результат="${s.executionResult}" [Самопроверка: ${s.verified ? "Экран обновился OK" : "Экран НЕ изменился!"}]')
            .join('\n');

    final planBlock = currentPlan.isEmpty
        ? 'План ещё не составлен (составь массив "plan" из 3-5 шагов!).'
        : currentPlan.join('\n');

    final userPrompt = '''
ЦЕЛЬ ПОЛЬЗОВАТЕЛЯ: $goal

ТЕКУЩИЙ ПЛАН (3-5 ШАГОВ):
$planBlock

СТАТУС САМОПРОВЕРКИ ПРОШЛОГО ШАГА:
${selfCheckWarning.isEmpty ? 'В порядке (экран меняется штатно).' : selfCheckWarning}

КОНТЕКСТ ПАМЯТИ И СОХРАНЁННЫХ СЦЕНАРИЕВ:
${memoryContext.isEmpty ? 'Нет записей' : memoryContext}

АКТИВНЫЙ ПАКЕТ НА ЭКРАНЕ: ${activePackage.isEmpty ? 'неизвестно' : activePackage}

ТЕКУЩЕЕ ДЕРЕВО UI ЭКРАНА:
${screenTree.isEmpty ? '[Экран пока пуст или мы внутри фоновой задачи. Можешь использовать web_research, compare_prices, book_service, open_app или wait.]' : screenTree}

СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЯ ВО ВРЕМЯ РАБОТЫ:
${userMessages.isEmpty ? 'нет' : userMessages}

ИСТОРИЯ ВЫПОЛНЕННЫХ ШАГОВ:
$historySummary

Верни JSON следующего шага (с полями "thought", "plan", "expected_change", "action"):
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
          if (es.contains('SocketException') ||
              es.contains('TimeoutException') ||
              es.contains('Failed host lookup')) {
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
          'reason': 'Не удалось получить ответ от моделей OpenRouter: $lastError',
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
        final thought = (map['thought'] ?? 'Выполняю шаг по плану').toString();
        final expectedChange =
            (map['expected_change'] ?? map['expectedChange'] ?? '').toString();
        final rawPlan = (map['plan'] as List?) ?? const [];
        final parsedPlan = rawPlan.map((e) => e.toString()).toList();
        final actionObj = map['action'];
        if (actionObj is Map) {
          return AiDecision(
            thought: thought,
            plan: parsedPlan,
            expectedScreenChange: expectedChange,
            action: AgentAction.fromJson(Map<String, dynamic>.from(actionObj)),
            rawResponse: jsonSlice,
          );
        }
        return AiDecision(
          thought: thought,
          plan: parsedPlan,
          expectedScreenChange: expectedChange,
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
