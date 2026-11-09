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
  List<File> _files = [];

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
      final mp3Dir = await ConverterService.outputDir();
      final vidDir = await ConverterService.videoDir();
      final list = <File>[
        ...mp3Dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mp3')),
        ...vidDir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mp4')),
      ]..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (mounted) setState(() => _files = list);
    } catch (_) {
      if (mounted) setState(() => _files = []);
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
        content: Text('$name\n\nКопия в системной папке «Музыка» или «Фильмы» останется.'),
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
        title: const Text('Мои файлы (MP3 и Видео)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _files.isEmpty
          ? const Center(child: Text('Папка пуста', style: TextStyle(color: Color(0xFF6B7280))))
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (_, i) {
                final f = _files[i];
                final n = f.path.split('/').last;
                final isVid = n.toLowerCase().endsWith('.mp4');
                return ListTile(
                  leading: Icon(
                    isVid ? Icons.video_file_rounded : Icons.audio_file_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${isVid ? "Видео без знака" : "MP3 с обложкой"} · ${_size(f)}'),
                  onTap: () => OpenFilex.open(f.path),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    onPressed: () => _delete(f),
                  ),
                );
              },
            ),
    );
  }
}
