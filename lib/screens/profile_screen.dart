import 'dart:io';
import 'package:flutter/material.dart';
import '../services/converter_service.dart';
import '../services/history_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _h = HistoryService();
  int _c = 0;

  @override
  void initState() {
    super.initState();
    _upd();
    historyChanged.addListener(_onChanged);
  }

  void _onChanged() => _upd();

  @override
  void dispose() {
    historyChanged.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _upd() async {
    final l = await _h.load();
    if (mounted) setState(() => _c = l.length);
  }

  Future<void> _showPath() async {
    final d = await ConverterService.outputDir();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Папка с MP3'),
        content: SelectableText(d.path),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))],
      ),
    );
  }

  Future<void> _clear() async {
    await _h.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История очищена (файлы остались)')),
      );
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить все MP3?'),
        content: const Text('Все сконвертированные файлы будут удалены без возможности восстановления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await ConverterService.outputDir();
      for (final e in d.listSync()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    await _h.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.person, size: 56, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Пользователь',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Сконвертировано файлов: $_c',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Папка с MP3'),
                  subtitle: const Text('Показать путь'),
                  onTap: _showPath,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.orange),
                  title: const Text('Очистить историю'),
                  subtitle: const Text('Файлы останутся на месте'),
                  onTap: _clear,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Удалить все MP3'),
                  subtitle: const Text('Файлы и историю'),
                  onTap: _deleteAll,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('О приложении'),
                  subtitle: const Text('Video→MP3 v1.5'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Video→MP3',
                    applicationVersion: '1.5',
                    applicationLegalese: '© 2026',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
