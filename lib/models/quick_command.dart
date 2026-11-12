class QuickCommand {
  final String id;
  final String emoji;
  final String title;
  final String goalPrompt;
  final String? cronSchedule;

  const QuickCommand({
    required this.id,
    required this.emoji,
    required this.title,
    required this.goalPrompt,
    this.cronSchedule,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'title': title,
        'goalPrompt': goalPrompt,
        'cronSchedule': cronSchedule,
      };

  factory QuickCommand.fromJson(Map<String, dynamic> json) => QuickCommand(
        id: (json['id'] ?? '').toString(),
        emoji: (json['emoji'] ?? '⚡').toString(),
        title: (json['title'] ?? '').toString(),
        goalPrompt: (json['goalPrompt'] ?? '').toString(),
        cronSchedule: json['cronSchedule']?.toString(),
      );

  static List<QuickCommand> defaultTemplates() => const [
        QuickCommand(
          id: 'cmd_smart_reply',
          emoji: '💬',
          title: 'Ответить на сообщения',
          goalPrompt: 'Прочитай все входящие уведомления из мессенджеров и предложи умные ответы или ответь "Буду через 10 минут"',
        ),
        QuickCommand(
          id: 'cmd_spam_shield',
          emoji: '🛡️',
          title: 'Антиспам-секретарь звонков',
          goalPrompt: 'Включи режим защиты от спам-звонков: отвечай незнакомым номерам, спрашивай "Кто это и по какому вопросу?" и присылай мне отчёт',
        ),
        QuickCommand(
          id: 'cmd_book_barber',
          emoji: '💈',
          title: 'Запись в барбершоп (поиск + звонок)',
          goalPrompt: 'Найди в интернете самый дешёвый барбершоп с хорошими отзывами, сравни цены и запиши меня на стрижку (через приложение или позвони им сам)',
        ),
        QuickCommand(
          id: 'cmd_book_doctor',
          emoji: '🩺',
          title: 'Запись к врачу (сравнение цен)',
          goalPrompt: 'Найди в интернете клиники, сравни цены на приём терапевта и запиши меня на ближайшее свободное время',
        ),
        QuickCommand(
          id: 'cmd_compare_prices',
          emoji: '🏷️',
          title: 'Найти где дешевле всего',
          goalPrompt: 'Изучи интернет и сравни цены на популярных площадках, покажи самый выгодный вариант в таблице',
        ),
        QuickCommand(
          id: 'cmd_max_msg',
          emoji: '📨',
          title: 'Сценарий: Написать в MAX',
          goalPrompt: 'Открой мессенджер MAX, найди нужный контакт через поиск и отправь сообщение',
        ),
        QuickCommand(
          id: 'cmd_alarm_7',
          emoji: '⏰',
          title: 'Будильник на 7:00',
          goalPrompt: 'Поставь будильник на 07:00 с меткой "Подъём" по будням',
        ),
        QuickCommand(
          id: 'cmd_torch',
          emoji: '🔦',
          title: 'Фонарик',
          goalPrompt: 'Включи фонарик на телефоне',
        ),
      ];
}
