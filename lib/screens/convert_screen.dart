import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../models/conversion_item.dart';
import '../services/converter_service.dart';
import '../services/queue_service.dart';
import 'trimmer_sheet.dart';

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});
  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final _conv = ConverterService();
  final _urlCtrl = TextEditingController();
  final _queue = QueueService.instance;

  String _urlMode = 'mp3'; // 'mp3' или 'video'
  int _bitrate = 192;
  bool _showQueueDetails = true;

  @override
  void initState() {
    super.initState();
    _conv.requestPermissions();
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() => _urlCtrl.text = data.text!.trim());
    }
  }

  void _submitUrls() {
    final raw = _urlCtrl.text.trim();
    if (raw.isEmpty) {
      _snack('Вставьте ссылку на YouTube, TikTok или Instagram');
      return;
    }
    final urls = ConverterService.extractAllUrls(raw);
    if (urls.isEmpty) {
      _queue.enqueueUrls([raw], mode: _urlMode, bitrateKbps: _bitrate);
    } else {
      _queue.enqueueUrls(urls, mode: _urlMode, bitrateKbps: _bitrate);
    }
    _urlCtrl.clear();
    FocusScope.of(context).unfocus();
    _snack('Добавлено в фоновую очередь (${urls.isEmpty ? 1 : urls.length} шт.)');
  }

  /// Выбор сразу 20+ видео из файлового менеджера или галереи (пакетная конвертация)
  Future<void> _pickMultipleVideos() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );
      if (res != null && res.files.isNotEmpty) {
        final paths = res.files.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          _queue.enqueueLocalFiles(paths, bitrateKbps: _bitrate);
          _snack('В очередь добавлено видео: ${paths.length} шт. Можно сворачивать приложение!');
        }
      }
    } catch (_) {
      _snack('Не удалось выбрать видеофайлы');
    }
  }

  /// Выбор одного файла сразу с открытием окна обрезки и редактирования тегов
  Future<void> _pickAndTrimSingleVideo() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.video);
      final path = res?.files.single.path;
      if (path != null && mounted) {
        final parsed = ConverterService.parseArtistAndTitle(path.split('/').last);
        final cover = await _conv.extractCoverFrame(path);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF1B1F26),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => TrimmerSheet(
            filePath: path,
            initialTitle: parsed['title'] ?? 'Track',
            initialArtist: parsed['artist'] ?? 'VideoToMp3',
            coverPath: cover,
          ),
        );
      }
    } catch (_) {
      _snack('Не удалось открыть файл для обрезки');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VideoToMp3 Pro', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Возможности',
            onPressed: () => showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Все 8 функций активны'),
                content: const SingleChildScrollView(
                  child: Text(
                    '1. Share-меню: Нажмите «Поделиться» в YouTube, TikTok или Instagram и выберите VideoToMp3.\n\n'
                    '2. Мини-окошко: Поверх приложения появится карточка «Видео без водяного знака или MP3?» — выбрали и она сразу закрылась.\n\n'
                    '3. Фоновая загрузка: Всё качается в фоне с прогрессом в шторке уведомлений.\n\n'
                    '4. Уведомление «Готово»: Нажмите на уведомление, чтобы сразу открыть трек или видео.\n\n'
                    '5. Без водяного знака: TikTok, YouTube и Instagram скачиваются в чистом оригинале.\n\n'
                    '6. Обрезка и Рингтон: Вырезайте припев с плавным затуханием и ставьте на звонок.\n\n'
                    '7. Авто-теги и обложка: Имя артиста, название и кадр-обложка вшиваются прямо в MP3.\n\n'
                    '8. Пакетная очередь: Выбирайте сразу 20+ видео или вставляйте список ссылок.',
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отлично')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // КАРТОЧКА 1: YouTube / TikTok / Instagram без водяного знака
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.public_rounded, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'YouTube · TikTok · Instagram (без водяного знака)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Вставьте одну или сразу несколько ссылок (либо отправьте через системное меню «Поделиться» из любого приложения)',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'https://vt.tiktok.com/... или YouTube / Instagram',
                      filled: true,
                      fillColor: const Color(0xFF121418),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2A303C)),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_rounded, color: Color(0xFF10B981)),
                        tooltip: 'Вставить',
                        onPressed: _pasteClipboard,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'mp3',
                              icon: Icon(Icons.music_note_rounded, size: 18),
                              label: Text('MP3 + Обложка'),
                            ),
                            ButtonSegment(
                              value: 'video',
                              icon: Icon(Icons.videocam_rounded, size: 18),
                              label: Text('Видео без знака'),
                            ),
                          ],
                          selected: {_urlMode},
                          onSelectionChanged: (s) => setState(() => _urlMode = s.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _submitUrls,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Скачать в фоне', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // КАРТОЧКА 2: Локальные видео, пакетная очередь 20+ видео и быстрая обрезка
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.layers_rounded, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Пакетная конвертация и Обрезка из телефона',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Выберите хоть 20 видео сразу — приложение само пропишет теги, вытащит обложки из кадра и сконвертирует всё в фоне.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickMultipleVideos,
                          icon: const Icon(Icons.playlist_add_check_rounded),
                          label: const Text('Выбрать 1–20+ видео'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A303C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickAndTrimSingleVideo,
                          icon: const Icon(Icons.content_cut_rounded, color: Color(0xFF10B981)),
                          label: const Text('Вырезать отрезок'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.high_quality_rounded, size: 18, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 8),
                      const Text('Качество MP3:', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      DropdownButton<int>(
                        value: _bitrate,
                        underline: const SizedBox(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _bitrate = v);
                            _queue.defaultBitrate = v;
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: 128, child: Text('128 kbps')),
                          DropdownMenuItem(value: 192, child: Text('192 kbps (Оптимально)')),
                          DropdownMenuItem(value: 256, child: Text('256 kbps')),
                          DropdownMenuItem(value: 320, child: Text('320 kbps (Максимум)')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // КАРТОЧКА 3: Очередь задач (прогресс каждого из 20+ файлов)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.queue_music_rounded, color: Color(0xFF10B981), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Фоновая очередь (${_queue.items.length})',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_queue.items.isNotEmpty)
                        TextButton(
                          onPressed: _queue.removeCompleted,
                          child: const Text('Очистить готовые', style: TextStyle(fontSize: 12)),
                        ),
                      IconButton(
                        icon: Icon(_showQueueDetails ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                        onPressed: () => setState(() => _showQueueDetails = !_showQueueDetails),
                      ),
                    ],
                  ),
                  if (_showQueueDetails) ...[
                    if (_queue.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Очередь пуста. Добавьте видео или поделитесь ссылкой из TikTok / YouTube / Instagram.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _queue.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 12, color: Color(0xFF2A303C)),
                        itemBuilder: (_, idx) {
                          final it = _queue.items[idx];
                          final isDone = it.status == QueueTaskStatus.completed;
                          final isErr = it.status == QueueTaskStatus.failed;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (it.coverPath != null && File(it.coverPath!).existsSync())
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        File(it.coverPath!),
                                        width: 38,
                                        height: 38,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    Icon(
                                      isDone
                                          ? Icons.check_circle_rounded
                                          : isErr
                                              ? Icons.error_outline_rounded
                                              : Icons.hourglass_top_rounded,
                                      color: isDone
                                          ? const Color(0xFF10B981)
                                          : isErr
                                              ? Colors.redAccent
                                              : Colors.amber,
                                    ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          it.customTitle.isNotEmpty ? it.customTitle : it.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                        ),
                                        Text(
                                          it.statusText,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isDone && it.outputPath != null)
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                      onPressed: () => OpenFilex.open(it.outputPath!),
                                    ),
                                ],
                              ),
                              if (it.status == QueueTaskStatus.downloading ||
                                  it.status == QueueTaskStatus.converting) ...[
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: it.progress > 0 ? it.progress : null,
                                  backgroundColor: const Color(0xFF121418),
                                  color: const Color(0xFF10B981),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
