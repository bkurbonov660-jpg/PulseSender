import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task_history.dart';
import '../services/agent_controller.dart';
import '../services/history_service.dart';
import '../widgets/agent_log_tile.dart';

class HistoryScreen extends StatefulWidget {
  final VoidCallback? onSwitchToAgentTab;

  const HistoryScreen({
    super.key,
    this.onSwitchToAgentTab,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryService _historyService = HistoryService.instance;
  String _filter = 'all';

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

  void _showTaskDetails(TaskHistory task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    task.isSuccess ? Icons.check_circle : Icons.error_outline,
                    color: task.isSuccess ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.goal,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Повторить задачу',
                    icon: const Icon(Icons.replay, color: Color(0xFF3F51B5)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onSwitchToAgentTab?.call();
                      AgentController.instance.runAgent(task.goal);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                'Старт: ${DateFormat('dd.MM.yyyy HH:mm:ss').format(task.startedAt)} · '
                'Длительность: ${task.duration.inSeconds} сек. · '
                'Шагов: ${task.steps.length}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                'Итог: ${task.finalStatus}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (task.plan.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'План: ${task.plan.join(" → ")}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF3F51B5)),
                ),
              ],
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: task.steps.length,
                  itemBuilder: (_, i) => AgentLogTile(step: task.steps[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _historyService.history;
    final filtered = all.where((item) {
      if (_filter == 'success') return item.isSuccess;
      if (_filter == 'error') return !item.isSuccess;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('История задач'),
        actions: [
          DropdownButton<String>(
            value: _filter,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Все')),
              DropdownMenuItem(value: 'success', child: Text('Успех')),
              DropdownMenuItem(value: 'error', child: Text('Ошибки')),
            ],
            onChanged: (v) => setState(() => _filter = v ?? 'all'),
          ),
          IconButton(
            tooltip: 'Очистить историю',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: all.isEmpty ? null : () => _historyService.clearHistory(),
          ),
        ],
      ),
      body: filtered.isEmpty
          ? const Center(
              child: Text(
                'История выполненных задач пуста',
                style: TextStyle(color: Colors.black54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              itemBuilder: (_, idx) {
                final item = filtered[idx];
                final dateStr = DateFormat('dd.MM HH:mm').format(item.startedAt);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.indigo.withOpacity(0.15)),
                  ),
                  child: ListTile(
                    onTap: () => _showTaskDetails(item),
                    leading: Icon(
                      item.isSuccess ? Icons.check_circle : Icons.error_outline,
                      color: item.isSuccess ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      item.goal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '$dateStr · ${item.finalStatus}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Chip(
                      label: Text('${item.steps.length} шаг.'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
