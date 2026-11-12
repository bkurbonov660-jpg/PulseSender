import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_action.dart';
import '../models/agent_step.dart';
import '../models/saved_scenario.dart';

class ScenarioService extends ChangeNotifier {
  static final ScenarioService instance = ScenarioService._();
  ScenarioService._();

  static const String _storageKey = 'pulse_agent_saved_scenarios_v2';
  List<SavedScenario> scenarios = [];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_storageKey) ?? const [];
    scenarios = raw
        .map((e) {
          try {
            return SavedScenario.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedScenario>()
        .toList();
    notifyListeners();
  }

  static String normalizeGoal(String goal) {
    return goal
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wа-яё\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Ищет подходящий сохранённый сценарий для быстрого прохождения без лишних запросов к модели
  SavedScenario? findMatchingScenario(String goal) {
    final norm = normalizeGoal(goal);
    if (norm.isEmpty) return null;

    for (final s in scenarios) {
      if (s.normalizedPattern == norm) return s;
    }

    final words = norm.split(' ').where((w) => w.length > 2).toSet();
    if (words.isEmpty) return null;

    SavedScenario? best;
    double bestScore = 0.0;
    for (final s in scenarios) {
      final sWords = s.normalizedPattern.split(' ').where((w) => w.length > 2).toSet();
      if (sWords.isEmpty) continue;
      final intersection = words.intersection(sWords).length;
      final union = words.union(sWords).length;
      final similarity = union > 0 ? intersection / union : 0.0;
      if (similarity >= 0.65 && similarity > bestScore) {
        bestScore = similarity;
        best = s;
      }
    }
    return best;
  }

  /// Сохраняет успешную последовательность шагов как готовый сценарий
  Future<void> recordSuccessfulRun({
    required String goal,
    required List<AgentStep> steps,
    required List<String> plan,
  }) async {
    final meaningfulActions = steps
        .map((s) => s.action)
        .where((a) => a.type != 'finish' && a.type != 'fail' && a.type != 'ask_user' && a.type != 'wait')
        .toList();
    if (meaningfulActions.isEmpty) return;

    final norm = normalizeGoal(goal);
    final existingIdx = scenarios.indexWhere((s) => s.normalizedPattern == norm);
    if (existingIdx >= 0) {
      final cur = scenarios[existingIdx];
      scenarios[existingIdx] = cur.copyWith(
        actions: meaningfulActions,
        planSteps: plan.isNotEmpty ? plan : cur.planSteps,
        successCount: cur.successCount + 1,
        updatedAt: DateTime.now(),
      );
    } else {
      scenarios.insert(
        0,
        SavedScenario(
          id: const Uuid().v4(),
          title: goal.trim(),
          normalizedPattern: norm,
          actions: meaningfulActions,
          planSteps: plan,
          successCount: 1,
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (scenarios.length > 100) {
      scenarios = scenarios.sublist(0, 100);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> deleteScenario(String id) async {
    scenarios.removeWhere((s) => s.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _storageKey,
      scenarios.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }
}
