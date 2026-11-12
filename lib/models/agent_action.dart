import 'dart:convert';

class AgentAction {
  final String type;
  final Map<String, dynamic> params;

  const AgentAction({
    required this.type,
    required this.params,
  });

  int? get target {
    final raw = params['target'] ?? params['index'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}');
  }

  String? get text => params['text']?.toString();
  String? get direction => params['direction']?.toString();
  String? get packageName => params['package']?.toString();
  String? get appName => params['app_name']?.toString() ?? params['appName']?.toString();
  String? get expectedChange =>
      params['expected_change']?.toString() ?? params['expectedChange']?.toString();
  String? get reason =>
      params['reason']?.toString() ??
      params['summary']?.toString() ??
      params['question']?.toString();

  static const Set<String> dangerousTypes = {
    'call',
    'call_contact',
    'ai_voice_call',
    'send_sms',
    'uninstall_app',
    'send_messenger',
    'send_email',
  };

  bool get isDangerous => dangerousTypes.contains(type);

  String get iconEmoji {
    switch (type) {
      case 'tap':
      case 'tap_xy':
      case 'long_press':
      case 'swipe':
      case 'scroll':
        return '👆';
      case 'input_text':
        return '⌨️';
      case 'call':
      case 'call_contact':
      case 'ai_voice_call':
      case 'answer_call':
      case 'end_call':
      case 'open_call_log':
        return '📞';
      case 'send_sms':
      case 'read_sms':
      case 'reply_notification':
        return '💬';
      case 'web_research':
      case 'compare_prices':
      case 'fetch_webpage':
      case 'search_web':
      case 'open_url':
        return '🌐';
      case 'book_service':
        return '💈';
      case 'set_alarm':
      case 'set_timer':
      case 'open_stopwatch':
      case 'dismiss_alarm':
      case 'show_alarms':
        return '⏰';
      case 'create_reminder':
      case 'create_calendar_event':
      case 'get_calendar_events':
        return '📅';
      case 'set_volume':
      case 'set_brightness':
      case 'toggle_wifi':
      case 'toggle_bluetooth':
      case 'toggle_airplane':
      case 'toggle_dnd':
      case 'toggle_flashlight':
      case 'vibrate':
      case 'open_power_saver':
        return '⚙️';
      case 'take_screenshot':
      case 'open_camera':
      case 'record_audio':
      case 'open_gallery':
        return '📸';
      case 'play_media':
      case 'next_track':
      case 'prev_track':
      case 'open_music_track':
        return '🎵';
      case 'open_map':
      case 'get_location':
      case 'call_taxi':
        return '📍';
      case 'finish':
        return '✅';
      case 'fail':
        return '⚠️';
      case 'ask_user':
        return '❓';
      default:
        return '🧠';
    }
  }

  String get humanReadableSummary {
    switch (type) {
      case 'tap':
        return 'Нажатие на элемент [${target ?? '?'}]';
      case 'tap_xy':
        return 'Нажатие по координатам (${params['x'] ?? '?'}, ${params['y'] ?? '?'})';
      case 'long_press':
        return 'Долгое нажатие на элемент [${target ?? '?'}]';
      case 'input_text':
        return 'Ввод текста "${text ?? ''}" в поле [${target ?? '?'}]';
      case 'scroll':
        return 'Скролл экрана (${direction ?? 'down'})';
      case 'swipe':
        return 'Свайп жест ${params['from'] ?? '${params['x1']},${params['y1']}'} → ${params['to'] ?? '${params['x2']},${params['y2']}'}';
      case 'open_app':
        return 'Открытие приложения ${packageName ?? appName ?? ''}';
      case 'navigate_back':
        return 'Системное действие: Назад';
      case 'navigate_home':
        return 'Системное действие: Домой';
      case 'navigate_recents':
        return 'Открытие недавних приложений';
      case 'navigate_notifications':
        return 'Открытие шторки уведомлений';
      case 'wait':
        return 'Ожидание ${params['seconds'] ?? 2} сек.';
      case 'wait_for':
        return 'Ожидание появления текста "${text ?? ''}"';
      case 'call':
        return 'Звонок на номер ${params['number'] ?? ''}';
      case 'call_contact':
        return 'Звонок контакту "${params['name'] ?? ''}"';
      case 'ai_voice_call':
        return 'Голосовой ИИ-звонок (${params['number'] ?? params['name'] ?? ''}): "${params['objective'] ?? params['script'] ?? 'Запись на услугу'}"';
      case 'answer_call':
        return 'Принятие входящего вызова';
      case 'end_call':
        return 'Завершение вызова';
      case 'open_call_log':
        return 'Открытие журнала вызовов';
      case 'send_sms':
        return 'Отправка SMS на ${params['number']}: "${text ?? ''}"';
      case 'read_sms':
        return 'Чтение последних SMS';
      case 'reply_notification':
        return 'Быстрый ответ на уведомление (${params['sender'] ?? 'чат'}): "${text ?? ''}"';
      case 'web_research':
        return 'Свободный ИИ-поиск в интернете: "${params['query'] ?? ''}"';
      case 'compare_prices':
        return 'Сравнение цен в интернете: "${params['item'] ?? params['query'] ?? ''}"';
      case 'fetch_webpage':
        return 'Изучение страницы: ${params['url'] ?? ''}';
      case 'book_service':
        return 'Запись на услугу (${params['service'] ?? 'услуга'}): ${params['place'] ?? ''} на ${params['time'] ?? 'ближайшее время'}';
      case 'set_alarm':
        final h = (params['hour'] ?? 7).toString().padLeft(2, '0');
        final m = (params['minute'] ?? 0).toString().padLeft(2, '0');
        return 'Установка будильника на $h:$m (${params['label'] ?? 'Будильник'})';
      case 'dismiss_alarm':
        return 'Отключение будильника';
      case 'show_alarms':
        return 'Открытие списка будильников';
      case 'set_timer':
        return 'Установка таймера на ${params['seconds'] ?? 60} сек. (${params['label'] ?? 'Таймер'})';
      case 'open_stopwatch':
        return 'Открытие секундомера';
      case 'create_reminder':
        return 'Создание напоминания "${params['title'] ?? ''}" (${params['datetime'] ?? ''})';
      case 'create_calendar_event':
        return 'Событие календаря "${params['title'] ?? ''}" (${params['start'] ?? ''})';
      case 'get_calendar_events':
        return 'Получение списка событий календаря';
      case 'find_contact':
        return 'Поиск контакта "${params['name'] ?? ''}"';
      case 'create_contact':
        return 'Создание контакта "${params['name'] ?? ''}" (${params['phone'] ?? ''})';
      case 'set_volume':
        return 'Громкость (${params['stream'] ?? 'music'}): ${params['level'] ?? 50}%';
      case 'set_brightness':
        return 'Яркость экрана: ${params['level'] ?? 80}%';
      case 'toggle_flashlight':
        return 'Фонарик: ${params['state'] == true ? 'ВКЛ' : 'ВЫКЛ'}';
      case 'toggle_wifi':
        return 'Панель Wi-Fi (${params['state'] == true ? 'ВКЛ' : 'ВЫКЛ'})';
      case 'toggle_bluetooth':
        return 'Настройки Bluetooth (${params['state'] == true ? 'ВКЛ' : 'ВЫКЛ'})';
      case 'toggle_airplane':
        return 'Настройки режима полёта';
      case 'toggle_dnd':
        return 'Режим Не беспокоить: ${params['state'] == true ? 'ВКЛ' : 'ВЫКЛ'}';
      case 'vibrate':
        return 'Вибрация ${params['ms'] ?? 500} мс';
      case 'take_screenshot':
        return 'Создание скриншота экрана';
      case 'open_camera':
        return 'Запуск камеры (${params['mode'] ?? 'photo'})';
      case 'record_audio':
        return 'Запись звука (${params['seconds'] ?? 10} сек.)';
      case 'open_gallery':
        return 'Открытие галереи';
      case 'open_url':
        return 'Открытие сайта ${params['url'] ?? ''}';
      case 'search_web':
        return 'Поиск в браузере: "${params['query'] ?? ''}"';
      case 'download_file':
        return 'Скачивание файла ${params['url'] ?? ''}';
      case 'open_map':
        return 'Маршрут на карте: "${params['address'] ?? ''}"';
      case 'call_taxi':
        return 'Вызов такси до "${params['address'] ?? params['destination'] ?? ''}"';
      case 'play_media':
        return 'Управление медиа: ${params['state'] ?? 'play'}';
      case 'next_track':
        return 'Следующий музыкальный трек';
      case 'prev_track':
        return 'Предыдущий музыкальный трек';
      case 'open_music_track':
        return 'Поиск трека "${params['query'] ?? ''}"';
      case 'get_battery':
        return 'Проверка заряда батареи';
      case 'check_network':
        return 'Проверка состояния сети';
      case 'get_location':
        return 'Получение GPS-координат';
      case 'list_apps':
        return 'Получение списка установленных приложений';
      case 'open_play_store':
        return 'Открытие Google Play (${params['package'] ?? ''})';
      case 'uninstall_app':
        return 'Удаление приложения (${params['package'] ?? ''})';
      case 'read_notifications':
        return 'Чтение активных уведомлений';
      case 'dismiss_notifications':
        return 'Очистка уведомлений';
      case 'send_email':
        return 'Отправка письма на ${params['to'] ?? ''}';
      case 'send_messenger':
        return 'Открытие чата ${params['app'] ?? 'telegram'} (${params['phone'] ?? ''})';
      case 'smart_home':
        return 'Управление умным домом';
      case 'finish':
        return 'Готово: ${reason ?? 'Задача выполнена'}';
      case 'fail':
        return 'Ошибка: ${reason ?? 'Не удалось выполнить'}';
      case 'ask_user':
        return 'Вопрос: ${reason ?? 'Уточните задачу'}';
      default:
        return 'Действие $type: ${jsonEncode(params)}';
    }
  }

  Map<String, dynamic> toJson() => {
        'action': type,
        ...params,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static String _normalizeType(String raw) {
    switch (raw.trim()) {
      case 'input':
        return 'input_text';
      case 'back':
        return 'navigate_back';
      case 'home':
        return 'navigate_home';
      case 'recents':
        return 'navigate_recents';
      case 'notifications':
        return 'navigate_notifications';
      case 'media_control':
        return 'play_media';
      case 'network_status':
        return 'check_network';
      case 'battery_info':
        return 'get_battery';
      case 'order_taxi':
        return 'call_taxi';
      case 'google_search':
        return 'web_research';
      case 'web_search':
        return 'web_research';
      case 'price_compare':
        return 'compare_prices';
      case 'voice_call':
        return 'ai_voice_call';
      case 'compose_email':
        return 'send_email';
      case 'open_messenger':
        return 'send_messenger';
      case 'done':
        return 'finish';
      default:
        return raw.trim();
    }
  }

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    final copy = Map<String, dynamic>.from(json);
    final rawType = (copy.remove('action') ?? copy.remove('type') ?? 'finish').toString();
    final normalized = _normalizeType(rawType);
    if (copy.containsKey('index') && !copy.containsKey('target')) {
      copy['target'] = copy['index'];
    }
    if (copy.containsKey('summary') && !copy.containsKey('reason')) {
      copy['reason'] = copy['summary'];
    }
    if (copy.containsKey('question') && !copy.containsKey('reason')) {
      copy['reason'] = copy['question'];
    }
    if (copy.containsKey('destination') && !copy.containsKey('address')) {
      copy['address'] = copy['destination'];
    }
    if (copy.containsKey('fileName') && !copy.containsKey('filename')) {
      copy['filename'] = copy['fileName'];
    }
    if (copy.containsKey('uri') && !copy.containsKey('deeplink')) {
      copy['deeplink'] = copy['uri'];
    }
    return AgentAction(
      type: normalized,
      params: copy,
    );
  }
}
