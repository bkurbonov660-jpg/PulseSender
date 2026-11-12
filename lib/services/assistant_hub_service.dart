import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/assistant_inbox_item.dart';
import 'ai_service.dart';
import 'settings_service.dart';
import 'system_actions_service.dart';
import 'voice_service.dart';

/// Единый центр для:
/// 1) Умных ответов на входящие сообщения (и автоответа на простые «буду через 10 минут»)
/// 2) Антиспам-секретаря звонков («Кто это и по какому вопросу?» + отчёт владельцу)
/// 3) Записи на услуги (врач, барбершоп, такси) и телефонных переговоров ИИ
class AssistantHubService extends ChangeNotifier {
  static final AssistantHubService instance = AssistantHubService._();
  AssistantHubService._();

  static const String _inboxKey = 'pulse_agent_inbox_items_v2';
  final SystemActionsService _sys = SystemActionsService();

  List<AssistantInboxItem> items = [];
  bool autoReplySimpleMessages = true;
  bool smartReplySuggestionsEnabled = true;
  bool spamCallSecretaryEnabled = true;
  String defaultQuickAutoReply = 'Буду через 10 минут, на связи!';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    autoReplySimpleMessages = p.getBool('auto_reply_simple_v2') ?? true;
    smartReplySuggestionsEnabled = p.getBool('smart_reply_suggest_v2') ?? true;
    spamCallSecretaryEnabled = p.getBool('spam_call_secretary_v2') ?? true;
    defaultQuickAutoReply =
        p.getString('default_quick_autoreply_v2') ?? 'Буду через 10 минут, на связи!';

    final raw = p.getStringList(_inboxKey) ?? const [];
    items = raw
        .map((e) {
          try {
            return AssistantInboxItem.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<AssistantInboxItem>()
        .toList();
    notifyListeners();
  }

  Future<void> setAutoReplySimple(bool val) async {
    autoReplySimpleMessages = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_reply_simple_v2', val);
    notifyListeners();
  }

  Future<void> setSmartReplySuggestions(bool val) async {
    smartReplySuggestionsEnabled = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('smart_reply_suggest_v2', val);
    notifyListeners();
  }

  Future<void> setSpamCallSecretary(bool val) async {
    spamCallSecretaryEnabled = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool('spam_call_secretary_v2', val);
    await _sys.setSpamProtectionMode(val);
    notifyListeners();
  }

  /// Вызывается при поступлении нового уведомления из мессенджера (MAX, Telegram, WhatsApp, SMS)
  Future<void> handleIncomingNotification({
    required String packageName,
    required String sender,
    required String text,
    required String key,
    required bool canReplyInline,
  }) async {
    if (!smartReplySuggestionsEnabled && !autoReplySimpleMessages) return;
    if (text.trim().isEmpty) return;

    final lower = text.toLowerCase();
    final isSimpleWhereQuestion = RegExp(
      r'(ты где|скоро будешь|когда будешь|через сколько|ждем тебя|вышел\??)',
    ).hasMatch(lower);

    String suggested = defaultQuickAutoReply;
    if (SettingsService.instance.hasValidApiKey) {
      suggested = await AiService.instance.generateQuickReply(
        sender: sender,
        incomingText: text,
        appPackage: packageName,
      );
    }

    // Если включён автоответ на простые сообщения и есть кнопка быстрого ответа в уведомлении
    if (autoReplySimpleMessages && isSimpleWhereQuestion && canReplyInline) {
      final sentOk = await _sys.replyToNotification(key: key, replyText: suggested);
      final item = AssistantInboxItem(
        id: const Uuid().v4(),
        kind: 'message_reply',
        title: '💬 Автоответ отправлен: $sender',
        subtitle: 'Входящее: "$text"',
        details: 'Агент автоматически ответил: "$suggested" ($packageName)',
        suggestedReply: suggested,
        notificationKey: key,
        isHandled: sentOk,
        timestamp: DateTime.now(),
      );
      await _addItem(item);
      return;
    }

    final item = AssistantInboxItem(
      id: const Uuid().v4(),
      kind: 'message_reply',
      title: '💬 Входящее от $sender',
      subtitle: text,
      details: 'Приложение: $packageName. Нажмите «Отправить», чтобы мгновенно ответить.',
      suggestedReply: suggested,
      notificationKey: key,
      isHandled: false,
      timestamp: DateTime.now(),
    );
    await _addItem(item);
  }

  /// Отправка предложенного ИИ ответа в 1 клик (по нажатию кнопки «Отправить»)
  Future<String> approveAndSendReply(AssistantInboxItem item, {String? customText}) async {
    final replyText = (customText ?? item.suggestedReply ?? defaultQuickAutoReply).trim();
    bool ok = false;
    if (item.notificationKey != null && item.notificationKey!.isNotEmpty) {
      ok = await _sys.replyToNotification(key: item.notificationKey!, replyText: replyText);
    }
    final idx = items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        suggestedReply: replyText,
        isHandled: true,
        details: ok
            ? '✅ Ответ отправлен напрямую: "$replyText"'
            : '✅ Ответ подготовлен: "$replyText"',
      );
      await _persist();
      notifyListeners();
    }
    return ok ? 'Ответ отправлен: "$replyText"' : 'Ответ сохранён: "$replyText"';
  }

  /// Вызывается при перехвате звонка от незнакомого номера (Антиспам-секретарь)
  Future<void> handleScreenedCall({
    required String phoneNumber,
    required String callerTranscript,
    required String actionTaken,
  }) async {
    String summary = callerTranscript.trim().isEmpty
        ? 'Абонент ничего не ответил после вопроса секретаря «Кто это и по какому вопросу?».'
        : 'Собеседник сказал: "$callerTranscript"';

    if (SettingsService.instance.hasValidApiKey && callerTranscript.trim().isNotEmpty) {
      summary = await AiService.instance.summarizeScreenedCall(
        phoneNumber: phoneNumber,
        transcript: callerTranscript,
      );
    }

    final reportItem = AssistantInboxItem(
      id: const Uuid().v4(),
      kind: 'spam_call',
      title: '🛡️ Проверен звонок: $phoneNumber',
      subtitle: actionTaken,
      details: 'Вопрос агента: «Здравствуйте! Кто это и по какому вопросу?»\nИтог разговора: $summary',
      phoneNumber: phoneNumber,
      isHandled: true,
      timestamp: DateTime.now(),
    );
    await _addItem(reportItem);
  }

  /// Имитация или запуск живого голосового звонка ИИ для записи на услуги (к врачу, в барбершоп)
  Future<String> runAiVoiceBookingCall({
    required String numberOrName,
    required String serviceName,
    required String preferredTime,
  }) async {
    final callResult = numberOrName.contains(RegExp(r'\d'))
        ? await _sys.makePhoneCall(numberOrName)
        : await _sys.callContactByName(numberOrName);

    final greeting =
        'Здравствуйте! Я голосовой помощник. Запишите, пожалуйста, клиента на $serviceName на время: $preferredTime.';
    await Future.delayed(const Duration(seconds: 2));
    await VoiceService.instance.speak(greeting);

    final item = AssistantInboxItem(
      id: const Uuid().v4(),
      kind: 'service_booking',
      title: '💈 Голосовая запись: $serviceName',
      subtitle: 'Контакт/номер: $numberOrName · Время: $preferredTime',
      details: 'Статус вызова: $callResult\nСказано голосом ИИ: "$greeting"',
      phoneNumber: numberOrName,
      isHandled: true,
      timestamp: DateTime.now(),
    );
    await _addItem(item);
    return 'Выполнен голосовой ИИ-звонок ($numberOrName) и озвучена просьба о записи на "$serviceName" ($preferredTime).';
  }

  Future<void> addCustomReport({
    required String kind,
    required String title,
    required String subtitle,
    required String details,
  }) async {
    await _addItem(
      AssistantInboxItem(
        id: const Uuid().v4(),
        kind: kind,
        title: title,
        subtitle: subtitle,
        details: details,
        isHandled: true,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _addItem(AssistantInboxItem item) async {
    items.insert(0, item);
    if (items.length > 100) {
      items = items.sublist(0, 100);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    items.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _inboxKey,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
