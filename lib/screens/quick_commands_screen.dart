import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/quick_command.dart';
import '../services/agent_controller.dart';
import '../services/automation_service.dart';
import '../services/history_service.dart';
import '../widgets/quick_command_card.dart';

class QuickCommandsScreen extends StatefulWidget {
  final VoidCallback onSwitchToAgentTab;

  const QuickCommandsScreen({
    super.key,
    required this.onSwitchToAgentTab,
  });

  @override
  State<QuickCommandsScreen> createState() => _QuickCommandsScreenState();
}

class _QuickCommandsScreenState extends State<QuickCommandsScreen> {
  final HistoryService _historyService = HistoryService.instance;

  @override
  void initState() {
    super.initState();
    _historyService.addListener(_onChanged);
  }

  @override
  void dispose() {
    _historyService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _runQuickCommand(QuickCommand cmd) {
    widget.onSwitchToAgentTab();
    AgentController.instance.runAgent(cmd.goalPrompt);
  }

  Future<void> _showCreateOrEditDialog({QuickCommand? existing}) async {
    final emojiCtrl = TextEditingController(text: existing?.emoji ?? '⚡');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final goalCtrl = TextEditingController(text: existing?.goalPrompt ?? '');
    bool daily8am = existing?.cronSchedule == '08:00';

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Создать свою команду' : 'Редактировать команду'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: emojiCtrl,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Иконка',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Название шаблона',
                          hintText: 'Запись в барбершоп',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: goalCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Команда для ИИ-агента',
                    hintText: 'Найди самый дешёвый барбершоп и запиши меня на завтра',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Автоматизация по расписанию', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Выполнять автоматически каждый день', style: TextStyle(fontSize: 11)),
                  value: daily8am,
                  onChanged: (v) => setSt(() => daily8am = v),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('Удалить', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete' && existing != null) {
      await _historyService.deleteQuickCommand(existing.id);
    } else if (action == 'save') {
      final title = titleCtrl.text.trim();
      final goal = goalCtrl.text.trim();
      if (title.isEmpty || goal.isEmpty) return;
      final cmd = QuickCommand(
        id: existing?.id ?? const Uuid().v4(),
        emoji: emojiCtrl.text.trim().isEmpty ? '⚡' : emojiCtrl.text.trim(),
        title: title,
        goalPrompt: goal,
        cronSchedule: daily8am ? '08:00' : null,
      );
      await _historyService.addOrUpdateQuickCommand(cmd);
      if (daily8am) {
        await AutomationService.instance.registerPeriodicAutomation(
          uniqueName: 'auto_${cmd.id}',
          goalPrompt: cmd.goalPrompt,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _historyService.quickCommands;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Быстрые команды'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                ),
                itemBuilder: (_, idx) {
                  final cmd = items[idx];
                  return QuickCommandCard(
                    command: cmd,
                    onTap: () => _runQuickCommand(cmd),
                    onLongPress: () => _showCreateOrEditDialog(existing: cmd),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _showCreateOrEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text('+ Создать свою команду'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
