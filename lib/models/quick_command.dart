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
          id: 'cmd_alarm_7',
          emoji: '⏰',
          title: 'Будильник на 7:00',
          goalPrompt: 'Поставь будильник на 07:00 с меткой "Подъём" по будням',
        ),
        QuickCommand(
          id: 'cmd_call_mom',
          emoji: '📞',
          title: 'Позвонить маме',
          goalPrompt: 'Позвони контакту Мама',
        ),
        QuickCommand(
          id: 'cmd_tg_msg',
          emoji: '💬',
          title: 'Написать в Telegram',
          goalPrompt: 'Открой Telegram и проверь новые сообщения',
        ),
        QuickCommand(
          id: 'cmd_water',
          emoji: '📅',
          title: 'Напоминание выпить воды',
          goalPrompt: 'Поставь таймер на 1800 секунд с меткой "Выпить воды" и создай напоминание в календаре',
        ),
        QuickCommand(
          id: 'cmd_music',
          emoji: '🎵',
          title: 'Включить музыку',
          goalPrompt: 'Включи воспроизведение музыки и установи громкость музыки на 70%',
        ),
        QuickCommand(
          id: 'cmd_torch',
          emoji: '🔦',
          title: 'Фонарик',
          goalPrompt: 'Включи фонарик на телефоне',
        ),
        QuickCommand(
          id: 'cmd_youtube',
          emoji: '🌐',
          title: 'Открыть YouTube',
          goalPrompt: 'Открой приложение YouTube (com.google.android.youtube)',
        ),
        QuickCommand(
          id: 'cmd_selfie',
          emoji: '📸',
          title: 'Сделать селфи',
          goalPrompt: 'Открой камеру в режиме фото',
        ),
      ];
}
