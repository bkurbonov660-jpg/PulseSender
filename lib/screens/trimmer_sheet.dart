import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/conversion_item.dart';
import '../services/converter_service.dart';
import '../services/history_service.dart';

class TrimmerSheet extends StatefulWidget {
  final String filePath;
  final String initialTitle;
  final String initialArtist;
  final String? coverPath;

  const TrimmerSheet({
    super.key,
    required this.filePath,
    required this.initialTitle,
    required this.initialArtist,
    this.coverPath,
  });

  @override
  State<TrimmerSheet> createState() => _TrimmerSheetState();
}

class _TrimmerSheetState extends State<TrimmerSheet> {
  final AudioPlayer _previewPlayer = AudioPlayer();
  final ConverterService _conv = ConverterService();
  final HistoryService _hist = HistoryService();

  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;

  double _totalDuration = 30.0;
  RangeValues _range = const RangeValues(0.0, 30.0);
  bool _fadeInOut = true;
  bool _isSaving = false;
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _artistCtrl = TextEditingController(text: widget.initialArtist);
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      final dur = await _previewPlayer.setFilePath(widget.filePath);
      final sec = (dur?.inMilliseconds ?? 30000) / 1000.0;
      if (mounted && sec > 1.0) {
        setState(() {
          _totalDuration = sec;
          _range = RangeValues(0.0, sec);
        });
      }
      _previewPlayer.positionStream.listen((pos) {
        final s = pos.inMilliseconds / 1000.0;
        if (_isPlayingPreview && s >= _range.end) {
          _previewPlayer.pause();
          if (mounted) setState(() => _isPlayingPreview = false);
        }
      });
    } catch (_) {
      final sec = await _conv.getDurationSeconds(widget.filePath);
      if (mounted && sec > 1.0) {
        setState(() {
          _totalDuration = sec;
          _range = RangeValues(0.0, sec);
        });
      }
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    super.dispose();
  }

  String _fmt(double sec) {
    final total = sec.round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePreview() async {
    if (_isPlayingPreview) {
      await _previewPlayer.pause();
      setState(() => _isPlayingPreview = false);
    } else {
      await _previewPlayer.seek(Duration(milliseconds: (_range.start * 1000).toInt()));
      _previewPlayer.play();
      setState(() => _isPlayingPreview = true);
    }
  }

  Future<void> _saveCut({required bool asRingtone}) async {
    await _previewPlayer.pause();
    setState(() {
      _isPlayingPreview = false;
      _isSaving = true;
    });

    final title = _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : widget.initialTitle;
    final artist = _artistCtrl.text.trim().isNotEmpty ? _artistCtrl.text.trim() : widget.initialArtist;

    final outPath = await _conv.trimAudioToMp3(
      inputPath: widget.filePath,
      startSec: _range.start,
      endSec: _range.end,
      bitrateKbps: 192,
      title: title,
      artist: artist,
      coverPath: widget.coverPath,
      fadeInOut: _fadeInOut,
    );

    if (outPath != null && File(outPath).existsSync()) {
      await _conv.saveToMusic(outPath);
      await _hist.add(ConversionItem(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        fileName: outPath.split('/').last,
        filePath: outPath,
        createdAt: DateTime.now(),
        bitrateKbps: 192,
        title: title,
        artist: artist,
        coverPath: widget.coverPath,
        isVideo: false,
        sourceType: 'cut',
      ));

      String msg = 'Отрезок сохранён в MP3!';
      if (asRingtone) {
        final ok = await _conv.setAsRingtone(outPath, title);
        msg = ok
            ? 'Установлено на звонок и сохранено в Музыку!'
            : 'Отрезок сохранён! Разрешите изменение системных настроек для установки рингтона.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, outPath);
      }
    } else {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обрезать файл')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cutLen = (_range.end - _range.start).clamp(0.0, _totalDuration);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut, size: 20, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Обрезка и теги',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _artistCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Исполнитель',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Старт: ${_fmt(_range.start)}', style: const TextStyle(fontSize: 12)),
              Text(
                'Длина: ${_fmt(cutLen)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
              ),
              Text('Конец: ${_fmt(_range.end)}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          RangeSlider(
            values: _range,
            min: 0.0,
            max: _totalDuration > 1.0 ? _totalDuration : 1.0,
            activeColor: const Color(0xFF2E7D32),
            onChanged: (v) {
              if (v.end - v.start >= 1.0) {
                setState(() => _range = v);
              }
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Плавное затухание по краям', style: TextStyle(fontSize: 13)),
            value: _fadeInOut,
            activeColor: const Color(0xFF2E7D32),
            onChanged: (v) => setState(() => _fadeInOut = v),
          ),
          const SizedBox(height: 8),
          if (_isSaving)
            const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
          else
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _togglePreview,
                  icon: Icon(_isPlayingPreview ? Icons.stop : Icons.play_arrow, size: 18),
                  label: Text(_isPlayingPreview ? 'Стоп' : 'Слушать', style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _saveCut(asRingtone: false),
                    icon: const Icon(Icons.music_note, size: 18),
                    label: const Text('В MP3', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _saveCut(asRingtone: true),
                  icon: const Icon(Icons.ring_volume, size: 18, color: Color(0xFF2E7D32)),
                  label: const Text('Рингтон', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
