import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/conversion_item.dart';
import 'converter_service.dart';
import 'history_service.dart';

/// Глобальный менеджер пакетной очереди (поддерживает 20+ видео или ссылок подряд в фоне)
class QueueService extends ChangeNotifier {
  static final QueueService instance = QueueService._();
  QueueService._();

  final ConverterService _conv = ConverterService();
  final HistoryService _hist = HistoryService();

  final List<QueueTaskItem> items = [];
  bool isRunning = false;
  int defaultBitrate = 192;
  bool saveToMusicFolder = true;

  int get pendingCount => items.where((e) => e.status == QueueTaskStatus.pending).length;
  int get completedCount => items.where((e) => e.status == QueueTaskStatus.completed).length;

  /// Добавляет список локальных видеофайлов (например, сразу 20 штук) и запускает очередь
  void enqueueLocalFiles(
    List<String> paths, {
    int? bitrateKbps,
    double? trimStartSec,
    double? trimEndSec,
  }) {
    final br = bitrateKbps ?? defaultBitrate;
    for (final p in paths) {
      final name = p.split('/').last;
      final parsed = ConverterService.parseArtistAndTitle(name);
      items.add(QueueTaskItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
        source: p,
        isUrl: false,
        displayName: parsed['title'] ?? name,
        customTitle: parsed['title'] ?? name,
        customArtist: parsed['artist'] ?? 'VideoToMp3',
        mode: 'mp3',
        bitrateKbps: br,
        trimStartSec: trimStartSec,
        trimEndSec: trimEndSec,
      ));
    }
    notifyListeners();
    processQueue();
  }

  /// Добавляет одну или сразу несколько ссылок (YouTube / TikTok / Instagram)
  void enqueueUrls(
    List<String> urls, {
    String mode = 'mp3',
    int? bitrateKbps,
    double? trimStartSec,
    double? trimEndSec,
  }) {
    final br = bitrateKbps ?? defaultBitrate;
    for (final u in urls) {
      final clean = u.trim();
      if (clean.isEmpty) continue;
      final platform = ConverterService.detectPlatform(clean);
      items.add(QueueTaskItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
        source: clean,
        isUrl: true,
        displayName: '${platform.toUpperCase()}: $clean',
        mode: mode,
        bitrateKbps: br,
        trimStartSec: trimStartSec,
        trimEndSec: trimEndSec,
      ));
    }
    notifyListeners();
    processQueue();
  }

  void removeCompleted() {
    items.removeWhere((e) => e.status == QueueTaskStatus.completed || e.status == QueueTaskStatus.failed);
    notifyListeners();
  }

  void cancelTask(String id) {
    items.removeWhere((e) => e.id == id && e.status == QueueTaskStatus.pending);
    notifyListeners();
  }

  Future<void> processQueue() async {
    if (isRunning) return;
    isRunning = true;
    notifyListeners();

    try {
      while (true) {
        final nextIndex = items.indexWhere((e) => e.status == QueueTaskStatus.pending);
        if (nextIndex == -1) break;

        final task = items[nextIndex];
        final totalActive = items.length;
        final currentNum = nextIndex + 1;

        if (task.isUrl) {
          task.status = QueueTaskStatus.downloading;
          task.progress = 0.05;
          task.statusText = 'Загрузка ($currentNum из $totalActive)...';
          notifyListeners();

          await _conv.updateForegroundNotification(
            title: 'Очередь ($currentNum/$totalActive): Загрузка',
            text: task.displayName,
            progress: 10,
          );

          final res = await _conv.downloadFromUrl(
            task.source,
            mode: task.mode,
            bitrateKbps: task.bitrateKbps,
            trimStartSec: task.trimStartSec,
            trimEndSec: task.trimEndSec,
            onProgress: (p, st) {
              task.progress = p;
              task.statusText = st;
              notifyListeners();
              _conv.updateForegroundNotification(
                title: 'Очередь ($currentNum/$totalActive)',
                text: '$st (${(p * 100).toInt()}%)',
                progress: (p * 100).toInt(),
              );
            },
          );

          if (res != null) {
            task.status = QueueTaskStatus.completed;
            task.progress = 1.0;
            task.outputPath = res.filePath;
            task.coverPath = res.coverPath;
            task.customTitle = res.title;
            task.customArtist = res.artist;
            task.statusText = res.isVideo ? 'Видео без водяного знака сохранено' : 'MP3 с обложкой готов';

            await _hist.add(ConversionItem(
              id: task.id,
              fileName: res.filePath.split('/').last,
              filePath: res.filePath,
              createdAt: DateTime.now(),
              bitrateKbps: task.bitrateKbps,
              title: res.title,
              artist: res.artist,
              coverPath: res.coverPath,
              isVideo: res.isVideo,
              sourceType: res.platform,
            ));

            await _conv.showCompletedNotification(
              title: 'Готово: ${res.title}',
              filePath: res.filePath,
              isVideo: res.isVideo,
            );
          } else {
            task.status = QueueTaskStatus.failed;
            task.statusText = 'Ошибка загрузки ссылки';
          }
        } else {
          // Локальный видеофайл
          task.status = QueueTaskStatus.converting;
          task.progress = 0.2;
          task.statusText = 'Извлечение обложки и тегов ($currentNum/$totalActive)...';
          notifyListeners();

          await _conv.updateForegroundNotification(
            title: 'Конвертация ($currentNum/$totalActive)',
            text: task.displayName,
            progress: ((currentNum - 1) * 100 ~/ totalActive).clamp(5, 95),
          );

          final cover = await _conv.extractCoverFrame(task.source);
          task.progress = 0.5;
          task.statusText = 'Кодирование MP3 ${task.bitrateKbps} kbps...';
          notifyListeners();

          final outPath = await _conv.convertToMp3(
            task.source,
            bitrateKbps: task.bitrateKbps,
            title: task.customTitle,
            artist: task.customArtist,
            coverImagePath: cover,
            trimStartSec: task.trimStartSec,
            trimEndSec: task.trimEndSec,
          );

          if (outPath != null && File(outPath).existsSync()) {
            if (saveToMusicFolder) {
              await _conv.saveToMusic(outPath);
            }
            task.status = QueueTaskStatus.completed;
            task.progress = 1.0;
            task.outputPath = outPath;
            task.coverPath = cover;
            task.statusText = 'MP3 + обложка готовы';

            await _hist.add(ConversionItem(
              id: task.id,
              fileName: outPath.split('/').last,
              filePath: outPath,
              createdAt: DateTime.now(),
              bitrateKbps: task.bitrateKbps,
              title: task.customTitle,
              artist: task.customArtist,
              coverPath: cover,
              isVideo: false,
              sourceType: 'local',
            ));

            await _conv.showCompletedNotification(
              title: 'Готово: ${task.customTitle}',
              filePath: outPath,
              isVideo: false,
            );
          } else {
            task.status = QueueTaskStatus.failed;
            task.statusText = 'Ошибка конвертации';
          }
        }
        notifyListeners();
      }
    } finally {
      isRunning = false;
      notifyListeners();
    }
  }
}
