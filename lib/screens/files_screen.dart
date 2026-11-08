import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../services/converter_service.dart';
import '../services/history_service.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<File> _f = [];

  @override
  void initState() {
    super.initState();
    _load();
    historyChanged.addListener(_onChanged);
  }

  void _onChanged() => _load();

  @override
  void dispose() {
    historyChanged.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dir = await ConverterService.outputDir();
      final list = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp3'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (mounted) setState(() => _f = list);
    } catch (_) {
      if (mounted) setState(() => _f = []);
    }
  }

  String _size(File f) {
    final b = f.lengthSync();
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _delete(File f) async {
    final name = f.path.split('/').last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text(name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await f.delete();
    } catch (_) {}
    await HistoryService().removeByPath(f.path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои файлы'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _f.isEmpty
          ? const Center(child: Text('Папка пуста'))
          : ListView.builder(
              itemCount: _f.length,
              itemBuilder: (_, i) {
                final f = _f[i];
                final n = f.path.split('/').last;
                return ListTile(
                  leading: const Icon(Icons.audio_file, color: Color(0xFF2E7D32)),
                  title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(f)),
                  onTap: () => OpenFilex.open(f.path),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _delete(f),
                  ),
                );
              },
            ),
    );
  }
}
