import '../models/agent_action.dart';
import '../services/accessibility_bridge.dart';
import '../services/assistant_hub_service.dart';
import '../services/system_actions_service.dart';
import '../services/voice_service.dart';
import '../services/web_research_service.dart';

class AgentActionDispatcher {
  final AccessibilityBridge accessibilityBridge;
  final SystemActionsService systemActions;

  const AgentActionDispatcher({
    required this.accessibilityBridge,
    required this.systemActions,
  });

  Future<String> dispatch(AgentAction action) async {
    final p = action.params;
    switch (action.type) {
      case 'tap':
        final ok = await accessibilityBridge.tapByIndex(
          action.target ?? 0,
          fallbackX: p['x'] as num?,
          fallbackY: p['y'] as num?,
        );
        return ok ? 'Тап выполнен' : 'Не удалось нажать на элемент';

      case 'tap_xy':
        final x = (p['x'] as num?)?.toInt() ?? 540;
        final y = (p['y'] as num?)?.toInt() ?? 1200;
        final ok = await accessibilityBridge.tapCoordinates(x, y);
        return ok ? 'Тап по ($x, $y) выполнен' : 'Не удалось нажать по координатам';

      case 'input_text':
        final fullText = action.text ?? '';
        final fieldIdx = action.target ?? 0;
        bool typedOk = false;
        final runesList = fullText.runes.toList();
        if (runesList.length <= 12 || p['live'] == false) {
          typedOk = await accessibilityBridge.inputTextByIndex(fieldIdx, fullText);
        } else {
          final stepLen = (runesList.length / 25).ceil().clamp(3, 80);
          for (int i = stepLen; i < runesList.length; i += stepLen) {
            await accessibilityBridge.inputTextByIndex(
              fieldIdx,
              String.fromCharCodes(runesList.sublist(0, i)),
            );
            await Future.delayed(const Duration(milliseconds: 90));
          }
          typedOk = await accessibilityBridge.inputTextByIndex(fieldIdx, fullText);
        }
        return typedOk
            ? 'Текст введён (${runesList.length} симв.)'
            : 'Не удалось ввести текст: поле [$fieldIdx] не редактируемое. Выбери элемент EditText.';

      case 'scroll':
        final ok = await accessibilityBridge.scrollScreen(action.direction ?? 'down');
        return ok ? 'Скролл выполнен' : 'Не удалось проскроллить';

      case 'swipe':
        final from = (p['from'] as List?);
        final to = (p['to'] as List?);
        final x1 = from != null && from.length >= 2
            ? (from[0] as num)
            : ((p['x1'] as num?) ?? 500);
        final y1 = from != null && from.length >= 2
            ? (from[1] as num)
            : ((p['y1'] as num?) ?? 1400);
        final x2 = to != null && to.length >= 2
            ? (to[0] as num)
            : ((p['x2'] as num?) ?? 500);
        final y2 = to != null && to.length >= 2
            ? (to[1] as num)
            : ((p['y2'] as num?) ?? 400);
        final durationMs = (p['duration_ms'] as num?)?.toInt() ?? 350;
        final ok = await accessibilityBridge.swipeGesture(
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          durationMs: durationMs,
        );
        return ok ? 'Свайп выполнен' : 'Ошибка свайпа';

      case 'long_press':
        final ok = await accessibilityBridge.longPressByIndex(
          action.target ?? 0,
          durationMs: (p['duration_ms'] as num?)?.toInt() ?? 800,
        );
        return ok ? 'Долгое нажатие выполнено' : 'Ошибка долгого нажатия';

      case 'open_app':
        bool opened = await systemActions.openApp(
          packageName: action.packageName,
          appName: action.appName,
        );
        if (!opened) {
          final nm = '${action.appName ?? ''} ${action.packageName ?? ''}'.toLowerCase();
          final nameTries = <String>[];
          final pkgTries = <String>[];
          if (nm.contains('макс') || nm.contains('max') || nm.contains('oneme')) {
            nameTries.addAll(['MAX', 'Макс']);
            pkgTries.add('ru.oneme.app');
          }
          if (nm.contains('замет') || nm.contains('note') || nm.contains('keep')) {
            nameTries.addAll(['Заметки', 'Notes', 'Заметка', 'Keep']);
            pkgTries.addAll([
              'com.miui.notes',
              'com.google.android.keep',
              'com.samsung.android.app.notes',
              'com.android.notes',
            ]);
          }
          if (nm.contains('telegram') || nm.contains('телеграм')) {
            pkgTries.addAll(['org.telegram.messenger', 'org.telegram.messenger.web']);
          }
          if (nm.contains('whatsapp') || nm.contains('ватсап') || nm.contains('вацап')) {
            pkgTries.add('com.whatsapp');
          }
          for (final pk in pkgTries) {
            if (opened) break;
            opened = await systemActions.openApp(packageName: pk);
          }
          for (final nmTry in nameTries) {
            if (opened) break;
            opened = await systemActions.openApp(appName: nmTry);
          }
          if (!opened && (action.appName ?? '').isNotEmpty) {
            opened = await systemActions.openApp(appName: action.appName);
          }
        }
        return opened
            ? 'Приложение открыто'
            : 'Приложение не найдено. Вызови list_apps, найди точное имя пакета и повтори open_app.';

      case 'navigate_back':
        await accessibilityBridge.performGlobalNav('back');
        return 'Нажато Назад';

      case 'navigate_home':
        await accessibilityBridge.performGlobalNav('home');
        return 'Нажато Домой';

      case 'navigate_recents':
        await accessibilityBridge.performGlobalNav('recents');
        return 'Открыты недавние';

      case 'navigate_notifications':
        await accessibilityBridge.performGlobalNav('notifications');
        return 'Открыта шторка уведомлений';

      case 'wait':
        final sec = (p['seconds'] as num?)?.toInt() ?? 2;
        await Future.delayed(Duration(seconds: sec.clamp(1, 30)));
        return 'Ожидание $sec сек. завершено';

      case 'wait_for':
        final targetText = (p['text'] ?? '').toString();
        final timeoutSec = (p['timeout'] as num?)?.toInt() ?? 10;
        final found = await accessibilityBridge.waitForText(
          targetText,
          timeoutSeconds: timeoutSec,
        );
        return found ? 'Текст "$targetText" появился' : 'Таймаут ожидания "$targetText"';

      case 'call':
        return await systemActions.makePhoneCall((p['number'] ?? '').toString());

      case 'call_contact':
        return await systemActions.callContactByName((p['name'] ?? '').toString());

      case 'ai_voice_call':
        final target = (p['number'] ?? p['name'] ?? '').toString();
        final service = (p['service'] ?? p['objective'] ?? 'Запись на услугу').toString();
        final time = (p['time'] ?? 'ближайшее время').toString();
        return await AssistantHubService.instance.runAiVoiceBookingCall(
          numberOrName: target,
          serviceName: service,
          preferredTime: time,
        );

      case 'answer_call':
        return await systemActions.answerRingingCall();

      case 'end_call':
        return await systemActions.endPhoneCall();

      case 'open_call_log':
        return await systemActions.openCallLog();

      case 'send_sms':
        return await systemActions.sendSms(
          number: (p['number'] ?? '').toString(),
          text: (p['text'] ?? '').toString(),
        );

      case 'read_sms':
        return await systemActions.readRecentSms(limit: (p['limit'] as num?)?.toInt() ?? 5);

      case 'reply_notification':
        final key = (p['key'] ?? '').toString();
        final text = (p['text'] ?? 'Буду через 10 минут').toString();
        final ok = await systemActions.replyToNotification(key: key, replyText: text);
        return ok ? 'Ответ на уведомление отправлен: "$text"' : 'Уведомление без прямого RemoteInput, откройте чат';

      case 'web_research':
        final q = (p['query'] ?? '').toString();
        final res = await WebResearchService.instance.searchInternetFree(q);
        return res;

      case 'compare_prices':
        final item = (p['item'] ?? p['query'] ?? '').toString();
        final report = await WebResearchService.instance.comparePricesOnline(item);
        await AssistantHubService.instance.addCustomReport(
          kind: 'price_comparison',
          title: '🏷️ Сравнение цен: $item',
          subtitle: 'Автоматический мониторинг цен в интернете',
          details: report,
        );
        return report;

      case 'fetch_webpage':
        final url = (p['url'] ?? '').toString();
        return await WebResearchService.instance.fetchWebpageText(url);

      case 'book_service':
        final service = (p['service'] ?? 'Услуга').toString();
        final place = (p['place'] ?? '').toString();
        final time = (p['time'] ?? 'ближайшее свободное время').toString();
        final phone = (p['phone'] ?? '').toString();
        if (phone.isNotEmpty) {
          return await AssistantHubService.instance.runAiVoiceBookingCall(
            numberOrName: phone,
            serviceName: '$service ($place)',
            preferredTime: time,
          );
        }
        final webInfo = await WebResearchService.instance.comparePricesOnline('$service $place запись онлайн');
        await AssistantHubService.instance.addCustomReport(
          kind: 'service_booking',
          title: '💈 Запись на услугу: $service',
          subtitle: '$place · Время: $time',
          details: webInfo,
        );
        return 'Найдены варианты записи для "$service ($place)" на $time:\n$webInfo';

      case 'set_alarm':
        final daysList = ((p['days'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList();
        return await systemActions.setAlarm(
          hour: (p['hour'] as num?)?.toInt() ?? 7,
          minute: (p['minute'] as num?)?.toInt() ?? 0,
          label: (p['label'] ?? 'PulseAgent').toString(),
          days: daysList,
          vibrate: p['vibrate'] != false,
        );

      case 'dismiss_alarm':
        return await systemActions.dismissAlarm();

      case 'show_alarms':
        return await systemActions.showAlarms();

      case 'set_timer':
        return await systemActions.setTimer(
          seconds: (p['seconds'] as num?)?.toInt() ?? 60,
          label: (p['label'] ?? 'Таймер').toString(),
        );

      case 'open_stopwatch':
        return await systemActions.openStopwatch();

      case 'create_reminder':
        return await systemActions.createReminder(
          title: (p['title'] ?? 'Напоминание').toString(),
          datetimeIso: (p['datetime'] ?? '').toString(),
          description: (p['description'] ?? '').toString(),
          minutesBefore: (p['minutes_before'] as num?)?.toInt() ?? 10,
          repeatRule: p['repeat']?.toString(),
        );

      case 'create_calendar_event':
        return await systemActions.createCalendarEvent(
          title: (p['title'] ?? 'Событие').toString(),
          startIso: (p['start'] ?? '').toString(),
          endIso: (p['end'] ?? '').toString(),
          location: (p['location'] ?? '').toString(),
          description: (p['description'] ?? '').toString(),
        );

      case 'get_calendar_events':
        return await systemActions.getUpcomingCalendarEvents(
          days: (p['days'] as num?)?.toInt() ?? 7,
        );

      case 'find_contact':
        return await systemActions.findContact((p['name'] ?? '').toString());

      case 'create_contact':
        return await systemActions.createContact(
          name: (p['name'] ?? '').toString(),
          phone: (p['phone'] ?? '').toString(),
        );

      case 'read_notifications':
        return await systemActions.readActiveNotifications();

      case 'dismiss_notifications':
        return await systemActions.dismissAllNotifications();

      case 'set_volume':
        return await systemActions.setVolume(
          stream: (p['stream'] ?? 'music').toString(),
          levelPercent: (p['level'] as num?)?.toInt() ?? 50,
        );

      case 'set_brightness':
        return await systemActions.setBrightness(
          levelPercent: (p['level'] as num?)?.toInt() ?? 80,
        );

      case 'toggle_wifi':
        return await systemActions.toggleWifi(p['state'] == true);

      case 'toggle_bluetooth':
        return await systemActions.toggleBluetooth(p['state'] == true);

      case 'toggle_airplane':
        return await systemActions.openAirplaneModeSettings();

      case 'toggle_dnd':
        return await systemActions.toggleDnd(p['state'] == true);

      case 'toggle_flashlight':
        return await systemActions.toggleFlashlight(p['state'] == true);

      case 'vibrate':
        return await systemActions.vibrate(ms: (p['ms'] as num?)?.toInt() ?? 500);

      case 'open_power_saver':
        return await systemActions.openPowerSaverSettings();

      case 'take_screenshot':
        return await accessibilityBridge.takeScreenshot();

      case 'open_camera':
        return await systemActions.openCamera(mode: (p['mode'] ?? 'photo').toString());

      case 'record_audio':
        return await systemActions.recordAudioClip(
          seconds: (p['seconds'] as num?)?.toInt() ?? 10,
        );

      case 'open_gallery':
        return await systemActions.openGallery();

      case 'play_media':
        return await systemActions.controlMedia((p['state'] ?? 'play').toString());

      case 'next_track':
        return await systemActions.controlMedia('next');

      case 'prev_track':
        return await systemActions.controlMedia('previous');

      case 'open_music_track':
        return await systemActions.openMusicTrack(
          query: (p['query'] ?? '').toString(),
          app: (p['app'] ?? 'spotify').toString(),
        );

      case 'check_network':
        return await systemActions.getNetworkStatus();

      case 'get_battery':
        return await systemActions.getBatteryInfo();

      case 'get_location':
        return await systemActions.getCurrentLocation();

      case 'open_map':
        return await systemActions.openMapAddress((p['address'] ?? '').toString());

      case 'call_taxi':
        return await systemActions.openTaxiDeepLink(
          destination: (p['address'] ?? p['destination'] ?? '').toString(),
        );

      case 'list_apps':
        return await systemActions.listInstalledApps();

      case 'open_play_store':
        return await systemActions.openPlayStore((p['package'] ?? '').toString());

      case 'uninstall_app':
        return await systemActions.uninstallApp((p['package'] ?? '').toString());

      case 'open_url':
        return await systemActions.openUrl((p['url'] ?? 'https://google.com').toString());

      case 'search_web':
        return await systemActions.searchGoogle((p['query'] ?? '').toString());

      case 'download_file':
        return await systemActions.downloadFile(
          url: (p['url'] ?? '').toString(),
          fileName: (p['filename'] ?? p['fileName'])?.toString(),
        );

      case 'send_email':
        return await systemActions.composeEmail(
          to: (p['to'] ?? '').toString(),
          subject: (p['subject'] ?? '').toString(),
          body: (p['body'] ?? '').toString(),
        );

      case 'send_messenger':
        return await systemActions.openMessengerChat(
          messenger: (p['app'] ?? 'telegram').toString(),
          phone: (p['phone'] ?? '').toString(),
          text: (p['text'] ?? '').toString(),
        );

      case 'smart_home':
        return await systemActions.triggerSmartHome(
          uri: (p['deeplink'] ?? p['uri'] ?? '').toString(),
          packageName: (p['package'] ?? 'com.google.android.apps.chromecast.app').toString(),
        );

      case 'say':
        final sayText = (p['text'] ?? action.reason ?? '').toString();
        await VoiceService.instance.speak(sayText);
        return 'Ответ пользователю: $sayText';

      case 'finish':
      case 'fail':
      case 'ask_user':
        return action.reason ?? 'Задача завершена';

      default:
        return 'Неизвестная команда: ${action.type}';
    }
  }
}
