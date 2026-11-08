import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import '../models/conversion_item.dart';
import '../services/history_service.dart';

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
  }

  void _onChanged() => _load();

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
    try {
      setState(() => _cur = it);
      await _p.setFilePath(it.filePath);
      _p.play();
    } catch (_) {
      _snack('Не удалось воспроизвести файл');
    }
  }

  @override
  void dispose() {
    historyChanged.removeListener(_onChanged);
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
                    Text(_cur!.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
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
          const Divider(),
          Expanded(
            child: _l.isEmpty
                ? const Center(child: Text('Нет сконвертированных файлов'))
                : ListView.builder(
                    itemCount: _l.length,
                    itemBuilder: (_, i) {
                      final it = _l[i];
                      return ListTile(
                        leading: const Icon(Icons.audiotrack),
                        title: Text(it.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${it.createdAt.toLocal().toString().substring(0, 16)} · ${it.bitrateKbps} kbps',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => _play(it)),
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
