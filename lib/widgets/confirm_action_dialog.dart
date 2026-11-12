import 'package:flutter/material.dart';
import '../models/agent_action.dart';
import '../services/settings_service.dart';

class ConfirmActionDialog extends StatelessWidget {
  final AgentAction action;

  const ConfirmActionDialog({super.key, required this.action});

  static Future<bool> show(BuildContext context, AgentAction action) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmActionDialog(action: action),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange),
      title: const Text('Подтверждение действия'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Агент хочет выполнить потенциально опасное действие:\n\n'
            '${action.iconEmoji} ${action.humanReadableSummary}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              action.toPrettyJson(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Нет', style: TextStyle(color: Colors.red)),
        ),
        OutlinedButton(
          onPressed: () async {
            await SettingsService.instance.allowActionForever(action.type);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Да навсегда'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Да'),
        ),
      ],
    );
  }
}
