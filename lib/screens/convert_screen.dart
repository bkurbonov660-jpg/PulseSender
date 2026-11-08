import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/conversion_item.dart';
import '../services/converter_service.dart';
import '../services/history_service.dart';

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
  final _hist = HistoryService();
  String? _path;
  String? _name;
  bool _busy = false;
  int _bitrate = 192;

  @override
  void initState() {
    super.initState();
    _svc.requestPermissions();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pick() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.video);
      if (r != null && r.files.single.path != null) {
        setState(() {
          _path = r.files.single.path;
          _name = r.files.single.name;
        });
      }
    } catch (_) {
      _snack('Не удалось выбрать файл');
    }
  }

  Future<void> _gallery() async {
    final ok = await _svc.requestPermissions();
    if (!ok) {
      _snack('Нет доступа к галерее — разреши в настройках телефона');
      return;
    }
    final v = await _svc.getVideos();
    if (!mounted) return;
    if (v.isEmpty) {
      _snack('Видео в галерее не найдены');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => ListView.builder(
        itemCount: v.length,
        itemBuilder: (_, i) => ListTile(
          leading: const Icon(Icons.video_file),
          title: Text(v[i].title ?? 'Видео ${i + 1}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () async {
            final f = await v[i].file;
            if (f != null && mounted) {
              setState(() {
                _path = f.path;
                _name = v[i].title ?? f.path.split('/').last;
              });
            }
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          },
        ),
      ),
    );
  }

  Future<void> _go() async {
    if (_path == null) return;
    setState(() => _busy = true);
    final out = await _svc.convertToMp3(_path!, bitrateKbps: _bitrate);
    if (out != null) {
      await _hist.add(ConversionItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        fileName: out.split('/').last,
        filePath: out,
        createdAt: DateTime.now(),
        bitrateKbps: _bitrate,
      ));
      _snack('Готово! MP3 сохранён — смотри вкладку «Плеер».');
    } else {
      _snack('Ошибка конвертации (возможно, в видео нет звука)');
    }
    if (mounted) {
      setState(() {
        _busy = false;
        if (out != null) {
          _path = null;
          _name = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Конвертер'),
        actions: [
          helpButton(
            context,
            'Как работает конвертер?',
            '1. Выбери видео из галереи или файловой системы.\n'
                '2. Выбери битрейт (качество MP3).\n'
                '3. Нажми «Конвертировать в MP3».\n\n'
                'Готовый файл появится на вкладке «Плеер» и в папке приложения.',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.movie_creation_outlined, size: 64, color: Color(0xFF2E7D32)),
                    const SizedBox(height: 12),
                    Text(
                      _name ?? 'Видео не выбрано',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _pick,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Файл'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _gallery,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Галерея'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.high_quality, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 12),
                    const Text('Битрейт:'),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _bitrate,
                      onChanged: _busy ? null : (v) => setState(() => _bitrate = v ?? 192),
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
            const SizedBox(height: 24),
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Конвертация… не закрывай приложение'),
            ] else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _path != null ? _go : null,
                  icon: const Icon(Icons.music_note),
                  label: const Text('Конвертировать в MP3'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            const Spacer(),
            const Text(
              'MP3 сохраняются в папку приложения',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
