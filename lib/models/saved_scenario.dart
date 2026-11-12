import 'agent_action.dart';

class SavedScenario {
  final String id;
  final String title;
  final String normalizedPattern;
  final List<AgentAction> actions;
  final List<String> planSteps;
  final int successCount;
  final DateTime updatedAt;

  const SavedScenario({
    required this.id,
    required this.title,
    required this.normalizedPattern,
    required this.actions,
    this.planSteps = const [],
    this.successCount = 1,
    required this.updatedAt,
  });

  SavedScenario copyWith({
    int? successCount,
    List<AgentAction>? actions,
    List<String>? planSteps,
    DateTime? updatedAt,
  }) =>
      SavedScenario(
        id: id,
        title: title,
        normalizedPattern: normalizedPattern,
        actions: actions ?? this.actions,
        planSteps: planSteps ?? this.planSteps,
        successCount: successCount ?? this.successCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'normalizedPattern': normalizedPattern,
        'actions': actions.map((a) => a.toJson()).toList(),
        'planSteps': planSteps,
        'successCount': successCount,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SavedScenario.fromJson(Map<String, dynamic> json) {
    final rawActions = (json['actions'] as List?) ?? const [];
    final rawPlan = (json['planSteps'] as List?) ?? const [];
    return SavedScenario(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      normalizedPattern: (json['normalizedPattern'] ?? '').toString(),
      actions: rawActions
          .map((e) => AgentAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      planSteps: rawPlan.map((e) => e.toString()).toList(),
      successCount: (json['successCount'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}
