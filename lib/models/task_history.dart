import 'agent_step.dart';

class TaskHistory {
  final String id;
  final String goal;
  final List<AgentStep> steps;
  final DateTime startedAt;
  final DateTime finishedAt;
  final bool isSuccess;
  final String finalStatus;

  const TaskHistory({
    required this.id,
    required this.goal,
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
    required this.isSuccess,
    required this.finalStatus,
  });

  Duration get duration => finishedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'steps': steps.map((e) => e.toJson()).toList(),
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'isSuccess': isSuccess,
        'finalStatus': finalStatus,
      };

  factory TaskHistory.fromJson(Map<String, dynamic> json) {
    final rawSteps = (json['steps'] as List?) ?? const [];
    return TaskHistory(
      id: (json['id'] ?? '').toString(),
      goal: (json['goal'] ?? '').toString(),
      steps: rawSteps
          .map((e) => AgentStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      startedAt: DateTime.tryParse((json['startedAt'] ?? '').toString()) ?? DateTime.now(),
      finishedAt: DateTime.tryParse((json['finishedAt'] ?? '').toString()) ?? DateTime.now(),
      isSuccess: (json['isSuccess'] ?? true) as bool,
      finalStatus: (json['finalStatus'] ?? 'Готово').toString(),
    );
  }
}
