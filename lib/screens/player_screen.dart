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
  final _p = AudioPlayer();
  final _h = HistoryService();
  List<ConversionItem> _l = [];
  ConversionItem? _cur;

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
    final found = _l.where((e) => e.filePath == reqPath).firstOrNull;
    if (found != null) {
      _play(found);
    } else if (File(reqPath).existsSync()) {
      _play(ConversionItem(
        id: 'ext',
        fileName: reqPath.split('/').last,
        filePath: reqPath,
        createdAt: DateTime.now(),
        bitrateKbps: 192,
      ));
    }
    activePlayRequestPath.value = null;
  }

  Future<void> _load() async {
    final l = await _h.load();
    if (mounted) setState(() => _l = l);
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _play(ConversionItem it) async {
    if (!File(it.filePath).existsSync()) {
      _snack('Файл не найден');
      return;
    }
    if (it.isVideo) {
      OpenFilex.open(it.filePath);
      return;
    }
    try {
      setState(() => _cur = it);
      await _p.setFilePath(it.filePath);
      _p.play();
    } catch (_) {
      _snack('Не удалось воспроизвести файл');
    }
  }

  void _openTrim(ConversionItem it) {
    if (!File(it.filePath).existsSync()) {
      _snack('Файл не найден');
      return;
    }
    _p.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
    _p.dispose();
    super.dispose();
  }

  Widget _seekBar() {
    return StreamBuilder<Duration?>(
      stream: _p.durationStream,
      builder: (_, ds) {
        final total = ds.data ?? Duration.zero;
        final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
        return StreamBuilder<Duration>(
          stream: _p.positionStream,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final val = pos.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
            return Slider(
              value: val,
              max: maxMs,
              onChanged: (v) => _p.seek(Duration(milliseconds: v.toInt())),
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
        title: const Text('Плеер'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (_cur != null)
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_cur!.coverPath != null && File(_cur!.coverPath!).existsSync())
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_cur!.coverPath!),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _cur!.title.isNotEmpty ? _cur!.title : _cur!.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              if (_cur!.artist.isNotEmpty)
                                Text(
                                  _cur!.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_cut, size: 20, color: Color(0xFF2E7D32)),
                          tooltip: 'Обрезать / Рингтон',
                          onPressed: () => _openTrim(_cur!),
                        ),
                      ],
                    ),
                    _seekBar(),
                    StreamBuilder<PlayerState>(
                      stream: _p.playerStateStream,
                      builder: (_, s) {
                        final playing = s.data?.playing ?? false;
                        return IconButton(
                          iconSize: 48,
                          icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          onPressed: () => playing ? _p.pause() : _p.play(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _l.isEmpty
                ? const Center(child: Text('Нет сконвертированных файлов'))
                : ListView.builder(
                    itemCount: _l.length,
                    itemBuilder: (_, i) {
                      final it = _l[i];
                      final hasCover = it.coverPath != null && File(it.coverPath!).existsSync();
                      return ListTile(
                        leading: hasCover
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(it.coverPath!),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                it.isVideo ? Icons.videocam : Icons.audiotrack,
                                color: const Color(0xFF2E7D32),
                              ),
                        title: Text(
                          it.title.isNotEmpty ? it.title : it.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${it.artist.isNotEmpty ? "${it.artist} · " : ""}${it.createdAt.toLocal().toString().substring(0, 16)} · ${it.isVideo ? "Видео" : "${it.bitrateKbps} kbps"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => _play(it),
                            ),
                            IconButton(
                              icon: const Icon(Icons.content_cut, size: 20),
                              tooltip: 'Обрезать',
                              onPressed: () => _openTrim(it),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new),
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
