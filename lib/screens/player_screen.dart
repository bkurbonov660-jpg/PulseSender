import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import '../models/conversion_item.dart';
import '../services/history_service.dart';
import 'trimmer_sheet.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = AudioPlayer();
  final _hist = HistoryService();
  List<ConversionItem> _items = [];
  ConversionItem? _current;

  @override
  void initState() {
    super.initState();
    _load();
    historyChanged.addListener(_onChanged);
    activePlayRequestPath.addListener(_onExternalPlayRequested);
  }

  void _onChanged() => _load();

  Future<void> _onExternalPlayRequested() async {
    final reqPath = activePlayRequestPath.value;
    if (reqPath == null || reqPath.isEmpty) return;
    await _load();
    final found = _items.where((e) => e.filePath == reqPath).firstOrNull;
    if (found != null) {
      _play(found);
    } else if (File(reqPath).existsSync()) {
      final temp = ConversionItem(
        id: 'ext',
        fileName: reqPath.split('/').last,
        filePath: reqPath,
        createdAt: DateTime.now(),
        bitrateKbps: 192,
        title: reqPath.split('/').last,
        artist: 'VideoToMp3',
      );
      _play(temp);
    }
    activePlayRequestPath.value = null;
  }

  Future<void> _load() async {
    final l = await _hist.load();
    if (mounted) setState(() => _items = l);
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _play(ConversionItem it) async {
    if (!File(it.filePath).existsSync()) {
      _snack('Файл не найден на устройстве');
      return;
    }
    if (it.isVideo) {
      OpenFilex.open(it.filePath);
      return;
    }
    try {
      setState(() => _current = it);
      await _player.setFilePath(it.filePath);
      _player.play();
    } catch (_) {
      _snack('Не удалось воспроизвести файл');
    }
  }

  void _openTrimmer(ConversionItem it) {
    if (!File(it.filePath).existsSync()) {
      _snack('Файл не найден');
      return;
    }
    _player.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TrimmerSheet(
        filePath: it.filePath,
        initialTitle: it.title.isNotEmpty ? it.title : it.fileName,
        initialArtist: it.artist.isNotEmpty ? it.artist : 'VideoToMp3',
        coverPath: it.coverPath,
      ),
    );
  }

  @override
  void dispose() {
    historyChanged.removeListener(_onChanged);
    activePlayRequestPath.removeListener(_onExternalPlayRequested);
    _player.dispose();
    super.dispose();
  }

  Widget _seekBar() {
    return StreamBuilder<Duration?>(
      stream: _player.durationStream,
      builder: (_, ds) {
        final total = ds.data ?? Duration.zero;
        final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
        return StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final val = pos.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
            return Slider(
              value: val,
              max: maxMs,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Плеер, Теги и Обрезка'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (_current != null)
            Card(
              margin: const EdgeInsets.all(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_current!.coverPath != null && File(_current!.coverPath!).existsSync())
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(_current!.coverPath!),
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A303C),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.music_note_rounded, size: 32, color: Color(0xFF10B981)),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _current!.title.isNotEmpty ? _current!.title : _current!.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _current!.artist.isNotEmpty ? _current!.artist : 'VideoToMp3',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_cut_rounded, color: Color(0xFF10B981)),
                          tooltip: 'Обрезать / Рингтон',
                          onPressed: () => _openTrimmer(_current!),
                        ),
                      ],
                    ),
                    _seekBar(),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (_, s) {
                        final playing = s.data?.playing ?? false;
                        return IconButton(
                          iconSize: 48,
                          color: const Color(0xFF10B981),
                          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded),
                          onPressed: () => playing ? _player.pause() : _player.play(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Пока нет готовых треков или видео',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      final hasCover = it.coverPath != null && File(it.coverPath!).existsSync();
                      return ListTile(
                        leading: hasCover
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(it.coverPath!),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B1F26),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  it.isVideo ? Icons.videocam_rounded : Icons.audiotrack_rounded,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                        title: Text(
                          it.title.isNotEmpty ? it.title : it.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${it.artist.isNotEmpty ? "${it.artist} · " : ""}${it.isVideo ? "Видео без знака" : "${it.bitrateKbps} kbps"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                        ),
                        onTap: () => _play(it),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.content_cut_rounded, size: 20, color: Color(0xFF10B981)),
                              tooltip: 'Обрезать припев / Рингтон',
                              onPressed: () => _openTrimmer(it),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new_rounded, size: 20),
                              onPressed: () => OpenFilex.open(it.filePath),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
