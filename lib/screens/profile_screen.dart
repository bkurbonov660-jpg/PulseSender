import 'package:flutter/material.dart';
import '../services/history_service.dart';
import '../services/scenario_service.dart';
import '../services/settings_service.dart';
import '../services/system_actions_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final HistoryService _history = HistoryService.instance;
  final ScenarioService _scenarios = ScenarioService.instance;
  final SystemActionsService _sys = SystemActionsService();

  @override
  void initState() {
    super.initState();
    _history.addListener(_onChanged);
    _scenarios.addListener(_onChanged);
  }

  @override
  void dispose() {
    _history.removeListener(_onChanged);
    _scenarios.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetEverything() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить всё?'),
        content: const Text(
          'История задач, сохранённые сценарии, быстрые команды и настройки будут возвращены к значениям по умолчанию.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Сбросить всё'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _history.clearHistory();
      await SettingsService.instance.resetAll();
      await _history.init();
      await _scenarios.init();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Все данные и настройки сброшены')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 44,
            backgroundColor: Color(0xFFE8EAF6),
            child: Icon(Icons.smart_toy, size: 48, color: Color(0xFF3F51B5)),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'PulseAgent v2.0 Autonomous AI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              'План + Самопроверка · Сценарии · Антиспам · Свободный Веб-ИИ',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              _statCard('Всего задач', '${_history.totalTasks}', Icons.task_alt, Colors.indigo),
              const SizedBox(width: 8),
              _statCard(
                  'Успешных', '${_history.successfulTasks}', Icons.check_circle_outline, Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _statCard('Сценариев в памяти', '${_scenarios.scenarios.length}', Icons.bolt,
                  Colors.orange),
              const SizedBox(width: 8),
              _statCard(
                'Среднее шагов',
                _history.averageSteps.toStringAsFixed(1),
                Icons.timeline,
                Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 20),

          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code, color: Color(0xFF3F51B5)),
                  title: const Text('GitHub Репозиторий'),
                  subtitle: const Text('github.com/bkurbonov660-jpg/PulseSender'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _sys.openUrl('https://github.com/bkurbonov660-jpg/PulseSender'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline, color: Color(0xFF3F51B5)),
                  title: Text('Модули v2.0'),
                  subtitle: Text(
                    '1) План 3-5 шагов + Самопроверка\n'
                    '2) Сохранённые сценарии\n'
                    '3) Умный ответ на сообщения\n'
                    '4) Отмена звонков от спама + отчёт\n'
                    '5) Запись на услуги + Голосовой звонок ИИ + Сравнение цен в интернете',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _resetEverything,
              icon: const Icon(Icons.restart_alt, color: Colors.red),
              label: const Text(
                'Сбросить всё',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
