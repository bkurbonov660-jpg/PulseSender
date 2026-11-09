import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../models/conversion_item.dart';
import '../services/converter_service.dart';
import '../services/queue_service.dart';
import 'trimmer_sheet.dart';

Widget helpButton(BuildContext context, String title, String text) {
  return IconButton(
    icon: const Icon(Icons.help_outline, size: 18, color: Color(0xFF9E9E9E)),
    tooltip: 'Подсказка',
    onPressed: () => showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Понятно')),
        ],
      ),
    ),
  );
}

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});
  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final _svc = ConverterService();
  final _queue = QueueService.instance;
  final _urlCtrl = TextEditingController();

  List<String> _selectedPaths = [];
  int _bitrate = 192;
  bool _saveMusic = true;
  String _urlMode = 'mp3';

  @override
  void initState() {
    super.initState();
    _svc.requestPermissions();
    _queue.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _queue.removeListener(_onQueueChanged);
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Выбор 1 или сразу 20+ видеофайлов
  Future<void> _pick() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
      if (r != null && r.files.isNotEmpty) {
        final paths = r.files.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          setState(() => _selectedPaths = paths);
        }
      }
    } catch (_) {
      _snack('Не удалось выбрать файл');
    }
  }

  Future<void> _gallery() async {
    try {
      final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (x != null && mounted) {
        setState(() => _selectedPaths = [x.path]);
      }
    } catch (_) {
      _snack('Не удалось открыть галерею');
    }
  }

  Future<void> _trimSelected() async {
    if (_selectedPaths.isEmpty) return;
    final path = _selectedPaths.first;
    final parsed = ConverterService.parseArtistAndTitle(path.split('/').last);
    final cover = await _svc.extractCoverFrame(path);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TrimmerSheet(
        filePath: path,
        initialTitle: parsed['title'] ?? 'Track',
        initialArtist: parsed['artist'] ?? 'VideoToMp3',
        coverPath: cover,
      ),
    );
  }

  void _go() {
    final urlText = _urlCtrl.text.trim();
    if (_selectedPaths.isEmpty && urlText.isEmpty) return;

    _queue.saveToMusicFolder = _saveMusic;
    _queue.defaultBitrate = _bitrate;

    if (_selectedPaths.isNotEmpty) {
      final count = _selectedPaths.length;
      _queue.enqueueLocalFiles(List<String>.from(_selectedPaths), bitrateKbps: _bitrate);
      setState(() => _selectedPaths = []);
      _snack(count == 1
          ? 'Конвертация запущена в фоне!'
          : 'В очередь добавлено $count видео! Всё сконвертируется в фоне.');
    }

    if (urlText.isNotEmpty) {
      final urls = ConverterService.extractAllUrls(urlText);
      _queue.enqueueUrls(urls.isEmpty ? [urlText] : urls, mode: _urlMode, bitrateKbps: _bitrate);
      _urlCtrl.clear();
      FocusScope.of(context).unfocus();
      _snack('Ссылка добавлена в фоновую загрузку!');
    }
  }

  String _selectedLabel() {
    if (_selectedPaths.isEmpty) return 'Видео не выбрано';
    if (_selectedPaths.length == 1) return _selectedPaths.first.split('/').last;
    return 'Выбрано видео: ${_selectedPaths.length} шт.';
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _selectedPaths.isNotEmpty || _urlCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Конвертер'),
        actions: [
          helpButton(
            context,
            'Как работает конвертер?',
            '1. Выбери 1 или сразу 20 видео из галереи/файлов, либо вставь ссылку (или поделись ею из TikTok, YouTube, Instagram).\n'
                '2. При необходимости нажми «Обрезать» для выбора припева или рингтона.\n'
                '3. Нажми «Конвертировать в MP3» — обложка и теги впишутся сами, а загрузка пойдёт в фоне.',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.movie_creation_outlined, size: 56, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 10),
                  Text(
                    _selectedLabel(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pick,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Файлы (1–20+)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _gallery,
                          icon: const Icon(Icons.photo_library, size: 18),
                          label: const Text('Галерея'),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedPaths.length == 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _trimSelected,
                        icon: const Icon(Icons.content_cut, size: 18, color: Color(0xFF2E7D32)),
                        label: const Text('Вырезать отрезок / Сделать рингтон'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.link, color: Color(0xFF2E7D32), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Ссылка (YouTube, TikTok, Instagram)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _urlMode,
                        isDense: true,
                        underline: const SizedBox(),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                        onChanged: (v) => setState(() => _urlMode = v ?? 'mp3'),
                        items: const [
                          DropdownMenuItem(value: 'mp3', child: Text('В MP3')),
                          DropdownMenuItem(value: 'video', child: Text('Видео без знака')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Вставь ссылку или поделись из приложения...',
                      hintStyle: const TextStyle(fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, size: 18, color: Color(0xFF2E7D32)),
                        tooltip: 'Вставить',
                        onPressed: () async {
                          final d = await Clipboard.getData(Clipboard.kTextPlain);
                          if (d?.text != null) {
                            setState(() => _urlCtrl.text = d!.text!.trim());
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.high_quality, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 12),
                  const Text('Битрейт:'),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _bitrate,
                    onChanged: (v) => setState(() => _bitrate = v ?? 192),
                    items: const [
                      DropdownMenuItem(value: 128, child: Text('128 kbps')),
                      DropdownMenuItem(value: 192, child: Text('192 kbps')),
                      DropdownMenuItem(value: 256, child: Text('256 kbps')),
                      DropdownMenuItem(value: 320, child: Text('320 kbps')),
                    ],
                  ),
                  helpButton(
                    context,
                    'Что такое битрейт?',
                    'Битрейт — это количество данных в секунду. Чем выше, тем лучше звук и больше файл.\n\n'
                        '• 128 kbps — для подкастов и экономии места\n'
                        '• 192 kbps — оптимально для музыки\n'
                        '• 256–320 kbps — для максимального качества',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.library_music, color: Color(0xFF2E7D32)),
              title: const Text('Сохранять в «Музыка»'),
              subtitle: const Text('Появится в плеере телефона с обложкой'),
              value: _saveMusic,
              onChanged: (v) => setState(() => _saveMusic = v),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: canStart ? _go : null,
              icon: const Icon(Icons.music_note),
              label: Text(_urlCtrl.text.trim().isNotEmpty && _urlMode == 'video'
                  ? 'Скачать видео без водяного знака'
                  : 'Конвертировать в MP3'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (_queue.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.queue_music, size: 18, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Очередь (${_queue.items.length})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: _queue.removeCompleted,
                          child: const Text('Очистить', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    ..._queue.items.map((it) {
                      final done = it.status == QueueTaskStatus.completed;
                      final err = it.status == QueueTaskStatus.failed;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  done
                                      ? Icons.check_circle
                                      : err
                                          ? Icons.error_outline
                                          : Icons.hourglass_top,
                                  size: 16,
                                  color: done
                                      ? const Color(0xFF2E7D32)
                                      : err
                                          ? Colors.red
                                          : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    it.customTitle.isNotEmpty ? it.customTitle : it.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                  it.statusText,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                if (done && it.outputPath != null)
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new, size: 16),
                                    onPressed: () => OpenFilex.open(it.outputPath!),
                                  ),
                              ],
                            ),
                            if (it.status == QueueTaskStatus.downloading ||
                                it.status == QueueTaskStatus.converting)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: LinearProgressIndicator(
                                  value: it.progress > 0 ? it.progress : null,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Копия MP3 хранится в приложении и в «Музыка/VideoToMp3»',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
