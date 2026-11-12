import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_command.dart';
import '../models/task_history.dart';

class HistoryService extends ChangeNotifier {
  static final HistoryService instance = HistoryService._();
  HistoryService._();

  static const String _historyKey = 'pulse_agent_task_history_v1';
  static const String _quickCommandsKey = 'pulse_agent_quick_commands_v1';

  List<TaskHistory> history = [];
  List<QuickCommand> quickCommands = [];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final rawHist = p.getStringList(_historyKey) ?? const [];
    history = rawHist
        .map((e) {
          try {
            return TaskHistory.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<TaskHistory>()
        .toList();
    history.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    final rawQuick = p.getStringList(_quickCommandsKey);
    if (rawQuick == null || rawQuick.isEmpty) {
      quickCommands = QuickCommand.defaultTemplates();
      await _saveQuickCommands();
    } else {
      quickCommands = rawQuick
          .map((e) {
            try {
              return QuickCommand.fromJson(jsonDecode(e) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<QuickCommand>()
          .toList();
    }
    notifyListeners();
  }

  Future<void> save(TaskHistory item) async {
    history.insert(0, item);
    if (history.length > 200) {
      history = history.sublist(0, 200);
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _historyKey,
      history.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_historyKey);
    notifyListeners();
  }

  String buildMemoryContext(String currentGoal) {
    if (history.isEmpty) return '';
    final lower = currentGoal.toLowerCase();
    if (lower.contains('как вчера') || lower.contains('повтори')) {
      final last = history.first;
      return 'Предыдущая выполненная задача пользователя была: "${last.goal}" (Статус: ${last.finalStatus}). Выполни аналогичную цель.';
    }
    final recent = history.take(3).map((h) => '- "${h.goal}" (${h.finalStatus})').join('\n');
    return 'Недавние задачи пользователя:\n$recent';
  }

  int get todayTaskCount {
    final now = DateTime.now();
    return history
        .where((h) =>
            h.startedAt.year == now.year &&
            h.startedAt.month == now.month &&
            h.startedAt.day == now.day)
        .length;
  }

  int get totalTasks => history.length;
  int get successfulTasks => history.where((h) => h.isSuccess).length;
  int get failedTasks => history.where((h) => !h.isSuccess).length;
  double get averageSteps {
    if (history.isEmpty) return 0.0;
    final sum = history.fold<int>(0, (acc, h) => acc + h.steps.length);
    return sum / history.length;
  }

  Future<void> addOrUpdateQuickCommand(QuickCommand cmd) async {
    final idx = quickCommands.indexWhere((c) => c.id == cmd.id);
    if (idx >= 0) {
      quickCommands[idx] = cmd;
    } else {
      quickCommands.add(cmd);
    }
    await _saveQuickCommands();
    notifyListeners();
  }

  Future<void> deleteQuickCommand(String id) async {
    quickCommands.removeWhere((c) => c.id == id);
    await _saveQuickCommands();
    notifyListeners();
  }

  Future<void> _saveQuickCommands() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _quickCommandsKey,
      quickCommands.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
