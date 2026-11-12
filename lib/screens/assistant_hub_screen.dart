import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/assistant_inbox_item.dart';
import '../services/agent_controller.dart';
import '../services/assistant_hub_service.dart';
import '../services/system_actions_service.dart';
import '../services/web_research_service.dart';

class AssistantHubScreen extends StatefulWidget {
  final VoidCallback onSwitchToAgentTab;

  const AssistantHubScreen({
    super.key,
    required this.onSwitchToAgentTab,
  });

  @override
  State<AssistantHubScreen> createState() => _AssistantHubScreenState();
}

class _AssistantHubScreenState extends State<AssistantHubScreen> {
  final AssistantHubService _hub = AssistantHubService.instance;
  final SystemActionsService _sys = SystemActionsService();
  String _selectedTab = 'all'; // all | message_reply | spam_call | service_booking

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onChanged);
  }

  @override
  void dispose() {
    _hub.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _testSpamCallSecretaryDialog() async {
    final numCtrl = TextEditingController(text: '+992 900 12 34 56');
    final speechCtrl = TextEditingController(
      text: 'Здравствуйте, это курьер доставки воды, стою у подъезда',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🛡️ Проверка Антиспам-секретаря'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Когда звонит незнакомый номер, агент отвечает голосом: «Кто это и по какому вопросу?», распознаёт речь и присылает вам отчёт.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numCtrl,
                decoration: const InputDecoration(
                  labelText: 'Незнакомый номер',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: speechCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Что ответил звонящий секретарю',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Проверить и создать отчёт'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _sys.simulateSpamCallScreening(numCtrl.text.trim(), speechCtrl.text.trim());
      await _hub.handleScreenedCall(
        phoneNumber: numCtrl.text.trim(),
        callerTranscript: speechCtrl.text.trim(),
        actionTaken: 'Ответил голосовой ИИ-секретарь (звонок отфильтрован)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отчёт секретаря по звонку добавлен в ленту!')),
        );
      }
    }
  }

  Future<void> _showBookingAndPriceDialog() async {
    final serviceCtrl = TextEditingController(text: 'Мужская стрижка в барбершопе');
    final timeCtrl = TextEditingController(text: 'Завтра в 16:00');
    final phoneCtrl = TextEditingController(text: '');
    String mode = 'compare_and_book'; // compare_and_book | voice_call

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('💈 Запись на услуги & Сравнение цен'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: serviceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Услуга (врач, барбершоп, такси, товар)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Желаемое время записи',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Телефон организации (если нужен живой звонок ИИ)',
                    hintText: 'Оставьте пустым для поиска в интернете/приложении',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: mode,
                  decoration: const InputDecoration(
                    labelText: 'Режим выполнения',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'compare_and_book',
                      child: Text('Найти самые дешёвые в интернете + Записать'),
                    ),
                    DropdownMenuItem(
                      value: 'voice_call',
                      child: Text('Позвонить с телефона и записать голосом ИИ'),
                    ),
                  ],
                  onChanged: (v) => setSt(() => mode = v ?? 'compare_and_book'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Запустить'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final srv = serviceCtrl.text.trim();
      final tm = timeCtrl.text.trim();
      final ph = phoneCtrl.text.trim();
      if (mode == 'voice_call' && ph.isNotEmpty) {
        final msg = await _hub.runAiVoiceBookingCall(
          numberOrName: ph,
          serviceName: srv,
          preferredTime: tm,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ищу самые выгодные предложения в интернете...')),
          );
        }
        final priceReport = await WebResearchService.instance.comparePricesOnline(srv);
        await _hub.addCustomReport(
          kind: 'service_booking',
          title: '💈 Сравнение цен и запись: $srv',
          subtitle: 'Желаемое время: $tm',
          details: priceReport,
        );
        widget.onSwitchToAgentTab();
        AgentController.instance.runAgent(
          'Найди самый дешёвый и лучший вариант для "$srv" на время "$tm" и запиши меня',
        );
      }
    }
  }

  Widget _buildItemCard(AssistantInboxItem item) {
    IconData icon;
    Color badgeColor;
    switch (item.kind) {
      case 'spam_call':
        icon = Icons.phone_callback_outlined;
        badgeColor = Colors.deepOrange;
        break;
      case 'service_booking':
      case 'price_comparison':
        icon = Icons.storefront_outlined;
        badgeColor = Colors.teal;
        break;
      default:
        icon = Icons.mark_chat_unread_outlined;
        badgeColor = const Color(0xFF3F51B5);
    }

    final timeStr = DateFormat('dd.MM HH:mm').format(item.timestamp);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: badgeColor.withOpacity(0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: badgeColor.withOpacity(0.12),
                  child: Icon(icon, color: badgeColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '$timeStr · ${item.subtitle}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                item.details,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            if (item.kind == 'message_reply' && item.suggestedReply != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Предложенный ответ: «${item.suggestedReply}»',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: item.isHandled
                        ? null
                        : () async {
                            final res = await _hub.approveAndSendReply(item);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(res)),
                              );
                            }
                          },
                    icon: Icon(item.isHandled ? Icons.check : Icons.send, size: 16),
                    label: Text(item.isHandled ? 'Отправлено' : 'Отправить'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF3F51B5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _hub.items.where((e) {
      if (_selectedTab == 'all') return true;
      if (_selectedTab == 'service_booking') {
        return e.kind == 'service_booking' || e.kind == 'price_comparison';
      }
      return e.kind == _selectedTab;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Автоответ, Антиспам & Услуги'),
        actions: [
          IconButton(
            tooltip: 'Очистить отчёты',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _hub.items.isEmpty ? null : _hub.clearAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            elevation: 0,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.reply_all, color: Color(0xFF3F51B5)),
                  title: const Text(
                    'Автоответ на простые сообщения',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Автоматически отвечать («${_hub.defaultQuickAutoReply}») или предлагать кнопку «Отправить»',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _hub.autoReplySimpleMessages,
                  onChanged: _hub.setAutoReplySimple,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined, color: Colors.deepOrange),
                  title: const Text(
                    'Отмена звонков от спама (ИИ-секретарь)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Отвечает незнакомым номерам: «Кто это и по какому вопросу?» и присылает вам текстовый отчёт',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _hub.spamCallSecretaryEnabled,
                  onChanged: _hub.setSpamCallSecretary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _testSpamCallSecretaryDialog,
                  icon: const Icon(Icons.phone_in_talk, size: 18),
                  label: const Text('Тест антиспам-звонка', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showBookingAndPriceDialog,
                  icon: const Icon(Icons.event_available, size: 18),
                  label: const Text('Запись & Сравнение цен', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3F51B5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Все события'),
                  selected: _selectedTab == 'all',
                  onSelected: (_) => setState(() => _selectedTab = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('💬 Сообщения'),
                  selected: _selectedTab == 'message_reply',
                  onSelected: (_) => setState(() => _selectedTab = 'message_reply'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('🛡️ Звонки / Спам'),
                  selected: _selectedTab == 'spam_call',
                  onSelected: (_) => setState(() => _selectedTab = 'spam_call'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('💈 Услуги и цены'),
                  selected: _selectedTab == 'service_booking',
                  onSelected: (_) => setState(() => _selectedTab = 'service_booking'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Пока нет отчётов. Здесь появляются входящие сообщения с кнопкой «Отправить», отчёты антиспам-секретаря о незнакомых звонках и результаты сравнения цен / записи на услуги.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            )
          else
            ...filtered.map(_buildItemCard),
        ],
      ),
    );
  }
}
