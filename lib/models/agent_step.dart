import 'agent_action.dart';

class AgentStep {
  final int index;
  final AgentAction action;
  final DateTime timestamp;
  final String screenSummary;
  final String executionResult;
  final bool verified;
  final String verificationNote;

  const AgentStep({
    required this.index,
    required this.action,
    required this.timestamp,
    this.screenSummary = '',
    this.executionResult = 'OK',
    this.verified = true,
    this.verificationNote = '',
  });

  int get stepNumber => index + 1;

  Map<String, dynamic> toJson() => {
        'index': index,
        'action': action.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'screenSummary': screenSummary,
        'executionResult': executionResult,
        'verified': verified,
        'verificationNote': verificationNote,
      };

  factory AgentStep.fromJson(Map<String, dynamic> json) => AgentStep(
        index: (json['index'] ?? 0) as int,
        action: AgentAction.fromJson(
          Map<String, dynamic>.from((json['action'] ?? {'action': 'finish'}) as Map),
        ),
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ?? DateTime.now(),
        screenSummary: (json['screenSummary'] ?? '').toString(),
        executionResult: (json['executionResult'] ?? 'OK').toString(),
        verified: (json['verified'] ?? true) as bool,
        verificationNote: (json['verificationNote'] ?? '').toString(),
      );
}
