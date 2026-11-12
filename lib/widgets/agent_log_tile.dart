import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/agent_step.dart';

class AgentLogTile extends StatelessWidget {
  final AgentStep step;

  const AgentLogTile({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm:ss').format(step.timestamp);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: step.verified
              ? Colors.indigo.withOpacity(0.18)
              : Colors.orange.withOpacity(0.6),
        ),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: step.verified ? const Color(0xFFE8EAF6) : const Color(0xFFFFF3E0),
          child: Text(
            step.action.iconEmoji,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Шаг ${step.index + 1}: ${step.action.humanReadableSummary}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(
              step.verified ? Icons.verified_outlined : Icons.sync_problem,
              size: 16,
              color: step.verified ? Colors.green : Colors.orange,
            ),
          ],
        ),
        subtitle: Text(
          '$timeStr · ${step.executionResult}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (step.verificationNote.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '🔍 Самопроверка: ${step.verificationNote}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: step.verified ? Colors.green[800] : Colors.orange[900],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              step.action.toPrettyJson(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF1A237E),
              ),
            ),
          ),
          if (step.screenSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '👁 Экран: ${step.screenSummary}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
