import 'package:flutter/services.dart';

class SystemActionsService {
  static const MethodChannel _channel = MethodChannel('com.pulseagent.app/agent');

  Future<bool> openApp({String? packageName, String? appName}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openApp', {
        'package': packageName ?? '',
        'appName': appName ?? '',
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> makePhoneCall(String number) async {
    try {
      return (await _channel.invokeMethod<String>('makeCall', {'number': number})) ??
          'Вызов начат';
    } catch (e) {
      return 'Ошибка вызова: $e';
    }
  }

  Future<String> callContactByName(String name) async {
    try {
      return (await _channel.invokeMethod<String>('callContact', {'name': name})) ??
          'Вызов контакта $name';
    } catch (e) {
      return 'Ошибка поиска контакта: $e';
    }
  }

  Future<String> endPhoneCall() async {
    try {
      return (await _channel.invokeMethod<String>('endCall')) ?? 'Вызов сброшен';
    } catch (e) {
      return 'Ошибка сброса вызова: $e';
    }
  }

  Future<String> openCallLog() async {
    try {
      return (await _channel.invokeMethod<String>('openCallLog')) ?? 'Журнал вызовов открыт';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> sendSms({required String number, required String text}) async {
    try {
      return (await _channel.invokeMethod<String>('sendSms', {
            'number': number,
            'text': text,
          })) ??
          'SMS отправлено';
    } catch (e) {
      return 'Ошибка отправки SMS: $e';
    }
  }

  Future<String> readRecentSms({int limit = 5}) async {
    try {
      return (await _channel.invokeMethod<String>('readSms', {'limit': limit})) ??
          'Нет SMS';
    } catch (e) {
      return 'Ошибка чтения SMS: $e';
    }
  }

  Future<String> setAlarm({
    required int hour,
    required int minute,
    required String label,
    List<int> days = const [],
    bool vibrate = true,
  }) async {
    try {
      return (await _channel.invokeMethod<String>('setAlarm', {
            'hour': hour,
            'minute': minute,
            'label': label,
            'days': days,
            'vibrate': vibrate,
          })) ??
          'Будильник установлен';
    } catch (e) {
      return 'Ошибка будильника: $e';
    }
  }

  Future<String> dismissAlarm() async {
    try {
      return (await _channel.invokeMethod<String>('dismissAlarm')) ?? 'Будильник отключён';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> showAlarms() async {
    try {
      return (await _channel.invokeMethod<String>('showAlarms')) ?? 'Открыты будильники';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> setTimer({required int seconds, required String label}) async {
    try {
      return (await _channel.invokeMethod<String>('setTimer', {
            'seconds': seconds,
            'label': label,
          })) ??
          'Таймер запущен';
    } catch (e) {
      return 'Ошибка таймера: $e';
    }
  }

  Future<String> openStopwatch() async {
    try {
      return (await _channel.invokeMethod<String>('openStopwatch')) ?? 'Секундомер открыт';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> createReminder({
    required String title,
    required String datetimeIso,
    String description = '',
    int minutesBefore = 10,
    String? repeatRule,
  }) async {
    try {
      return (await _channel.invokeMethod<String>('createReminder', {
            'title': title,
            'datetime': datetimeIso,
            'description': description,
            'minutesBefore': minutesBefore,
            'repeat': repeatRule ?? '',
          })) ??
          'Напоминание создано';
    } catch (e) {
      return 'Ошибка напоминания: $e';
    }
  }

  Future<String> createCalendarEvent({
    required String title,
    required String startIso,
    required String endIso,
    String location = '',
    String description = '',
  }) async {
    try {
      return (await _channel.invokeMethod<String>('createCalendarEvent', {
            'title': title,
            'start': startIso,
            'end': endIso,
            'location': location,
            'description': description,
          })) ??
          'Событие добавлено в календарь';
    } catch (e) {
      return 'Ошибка календаря: $e';
    }
  }

  Future<String> getUpcomingCalendarEvents({int days = 7}) async {
    try {
      return (await _channel.invokeMethod<String>('getCalendarEvents', {'days': days})) ??
          'Событий не найдено';
    } catch (e) {
      return 'Ошибка чтения календаря: $e';
    }
  }

  Future<String> findContact(String name) async {
    try {
      return (await _channel.invokeMethod<String>('findContact', {'name': name})) ??
          'Контакт не найден';
    } catch (e) {
      return 'Ошибка поиска контакта: $e';
    }
  }

  Future<String> createContact({required String name, required String phone}) async {
    try {
      return (await _channel.invokeMethod<String>('createContact', {
            'name': name,
            'phone': phone,
          })) ??
          'Открыто создание контакта';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> readActiveNotifications() async {
    try {
      return (await _channel.invokeMethod<String>('readNotifications')) ??
          'Активных уведомлений нет';
    } catch (e) {
      return 'Ошибка чтения уведомлений: $e';
    }
  }

  Future<String> dismissAllNotifications() async {
    try {
      return (await _channel.invokeMethod<String>('dismissNotifications')) ??
          'Уведомления очищены';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> setVolume({required String stream, required int levelPercent}) async {
    try {
      return (await _channel.invokeMethod<String>('setVolume', {
            'stream': stream,
            'level': levelPercent.clamp(0, 100),
          })) ??
          'Громкость установлена';
    } catch (e) {
      return 'Ошибка громкости: $e';
    }
  }

  Future<String> setBrightness({required int levelPercent}) async {
    try {
      return (await _channel.invokeMethod<String>('setBrightness', {
            'level': levelPercent.clamp(0, 100),
          })) ??
          'Яркость установлена';
    } catch (e) {
      return 'Ошибка яркости: $e';
    }
  }

  Future<String> toggleWifi(bool enable) async {
    try {
      return (await _channel.invokeMethod<String>('toggleWifi', {'state': enable})) ??
          'Открыта панель Wi-Fi';
    } catch (e) {
      return 'Ошибка Wi-Fi: $e';
    }
  }

  Future<String> toggleBluetooth(bool enable) async {
    try {
      return (await _channel.invokeMethod<String>('toggleBluetooth', {'state': enable})) ??
          'Открыты настройки Bluetooth';
    } catch (e) {
      return 'Ошибка Bluetooth: $e';
    }
  }

  Future<String> openAirplaneModeSettings() async {
    try {
      return (await _channel.invokeMethod<String>('toggleAirplane')) ??
          'Открыты настройки режима полёта';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> toggleDnd(bool enable) async {
    try {
      return (await _channel.invokeMethod<String>('toggleDnd', {'state': enable})) ??
          'Режим Не беспокоить переключён';
    } catch (e) {
      return 'Ошибка DND: $e';
    }
  }

  Future<String> toggleFlashlight(bool enable) async {
    try {
      return (await _channel.invokeMethod<String>('toggleFlashlight', {'state': enable})) ??
          'Фонарик переключён';
    } catch (e) {
      return 'Ошибка фонарика: $e';
    }
  }

  Future<String> vibrate({int ms = 500}) async {
    try {
      return (await _channel.invokeMethod<String>('vibrate', {'ms': ms})) ?? 'Вибрация';
    } catch (e) {
      return 'Ошибка вибро: $e';
    }
  }

  Future<String> openPowerSaverSettings() async {
    try {
      return (await _channel.invokeMethod<String>('openPowerSaver')) ??
          'Открыты настройки энергосбережения';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> openCamera({String mode = 'photo'}) async {
    try {
      return (await _channel.invokeMethod<String>('openCamera', {'mode': mode})) ??
          'Камера открыта';
    } catch (e) {
      return 'Ошибка камеры: $e';
    }
  }

  Future<String> recordAudioClip({int seconds = 10}) async {
    try {
      return (await _channel.invokeMethod<String>('recordAudio', {'seconds': seconds})) ??
          'Аудио записано';
    } catch (e) {
      return 'Ошибка записи звука: $e';
    }
  }

  Future<String> openGallery() async {
    try {
      return (await _channel.invokeMethod<String>('openGallery')) ?? 'Галерея открыта';
    } catch (e) {
      return 'Ошибка галереи: $e';
    }
  }

  Future<String> controlMedia(String state) async {
    try {
      return (await _channel.invokeMethod<String>('controlMedia', {'state': state})) ??
          'Медиа команда отправлена ($state)';
    } catch (e) {
      return 'Ошибка медиа: $e';
    }
  }

  Future<String> openMusicTrack({required String query, String app = 'spotify'}) async {
    try {
      return (await _channel.invokeMethod<String>('openMusicTrack', {
            'query': query,
            'app': app,
          })) ??
          'Поиск трека запущен';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> getNetworkStatus() async {
    try {
      return (await _channel.invokeMethod<String>('getNetworkStatus')) ?? 'Статус сети неизвестен';
    } catch (e) {
      return 'Ошибка сети: $e';
    }
  }

  Future<String> getBatteryInfo() async {
    try {
      return (await _channel.invokeMethod<String>('getBatteryInfo')) ?? 'Нет данных батареи';
    } catch (e) {
      return 'Ошибка батареи: $e';
    }
  }

  Future<String> getCurrentLocation() async {
    try {
      return (await _channel.invokeMethod<String>('getLocation')) ?? 'Координаты не получены';
    } catch (e) {
      return 'Ошибка геолокации: $e';
    }
  }

  Future<String> openMapAddress(String address) async {
    try {
      return (await _channel.invokeMethod<String>('openMap', {'address': address})) ??
          'Карта открыта';
    } catch (e) {
      return 'Ошибка карты: $e';
    }
  }

  Future<String> openTaxiDeepLink({required String destination}) async {
    try {
      return (await _channel.invokeMethod<String>('openTaxi', {'destination': destination})) ??
          'Открыто приложение такси / карта';
    } catch (_) {
      return await openMapAddress(destination);
    }
  }

  Future<String> listInstalledApps() async {
    try {
      return (await _channel.invokeMethod<String>('listApps')) ?? '';
    } catch (e) {
      return 'Ошибка списка приложений: $e';
    }
  }

  Future<String> openPlayStore(String packageName) async {
    try {
      return (await _channel.invokeMethod<String>('openPlayStore', {'package': packageName})) ??
          'Открыт Google Play';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  Future<String> uninstallApp(String packageName) async {
    try {
      return (await _channel.invokeMethod<String>('uninstallApp', {'package': packageName})) ??
          'Запрос удаления отправлен';
    } catch (e) {
      return 'Ошибка удаления: $e';
    }
  }

  Future<String> openUrl(String url) async {
    final normalized = url.startsWith('http') ? url : 'https://$url';
    try {
      await _channel.invokeMethod('openUrl', {'url': normalized});
      return 'Открыт URL: $normalized';
    } catch (e) {
      return 'Ошибка открытия ссылки: $e';
    }
  }

  Future<String> searchGoogle(String query) async {
    final searchUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';
    return await openUrl(searchUrl);
  }

  Future<String> downloadFile({required String url, String? fileName}) async {
    try {
      return (await _channel.invokeMethod<String>('downloadFile', {
            'url': url,
            'fileName': fileName ?? 'download_${DateTime.now().millisecondsSinceEpoch}',
          })) ??
          'Загрузка запущена через DownloadManager';
    } catch (e) {
      return 'Ошибка загрузки: $e';
    }
  }

  Future<String> composeEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      return (await _channel.invokeMethod<String>('composeEmail', {
            'to': to,
            'subject': subject,
            'body': body,
          })) ??
          'Открыто окно написания письма для $to';
    } catch (e) {
      return 'Ошибка почты: $e';
    }
  }

  Future<String> openMessengerChat({
    required String messenger,
    required String phone,
    String text = '',
  }) async {
    try {
      return (await _channel.invokeMethod<String>('openMessenger', {
            'app': messenger,
            'phone': phone,
            'text': text,
          })) ??
          'Мессенджер открыт';
    } catch (e) {
      return 'Ошибка мессенджера: $e';
    }
  }

  Future<String> triggerSmartHome({
    required String uri,
    required String packageName,
  }) async {
    if (uri.isNotEmpty) {
      await openUrl(uri);
      return 'Сценарий умного дома запущен';
    }
    await openApp(packageName: packageName);
    return 'Открыто приложение Умного дома';
  }

  Future<void> updateAgentProgressNotification({
    required String title,
    required String body,
    required int step,
    required int maxSteps,
    bool ongoing = true,
  }) async {
    try {
      await _channel.invokeMethod('updateAgentNotification', {
        'title': title,
        'body': body,
        'step': step,
        'maxSteps': maxSteps,
        'ongoing': ongoing,
      });
    } catch (_) {}
  }

  Future<void> scheduleExactGoal({
    required String goal,
    required int delaySeconds,
  }) async {
    try {
      await _channel.invokeMethod('scheduleDelayedGoal', {
        'goal': goal,
        'delaySeconds': delaySeconds,
      });
    } catch (_) {}
  }

  Future<void> requestRuntimePermissions() async {
    try {
      await _channel.invokeMethod('requestRuntimePermissions');
    } catch (_) {}
  }
}
