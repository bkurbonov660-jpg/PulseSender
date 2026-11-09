import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MediaMetadata {
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final double durationSec;

  MediaMetadata({
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.durationSec = 0,
  });
}

class DownloadResult {
  final String filePath;
  final String title;
  final String artist;
  final String? coverPath;
  final bool isVideo;
  final String platform;

  DownloadResult({
    required this.filePath,
    required this.title,
    required this.artist,
    this.coverPath,
    required this.isVideo,
    required this.platform,
  });
}

class ConverterService {
  static const MethodChannel mediaChannel = MethodChannel('vtomp3/media');

  Future<void> requestPermissions() async {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  static Future<Directory> outputDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/mp3');
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  static Future<Directory> videoDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/videos');
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  static Future<Directory> coversDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/covers');
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  /// Определяет платформу по ссылке
  static String detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('tiktok.com') || u.contains('vm.tiktok') || u.contains('vt.tiktok')) {
      return 'tiktok';
    }
    if (u.contains('instagram.com') || u.contains('instagr.am')) {
      return 'instagram';
    }
    if (u.contains('youtube.com') || u.contains('youtu.be')) {
      return 'youtube';
    }
    return 'url';
  }

  /// Авто-разбор Названия и Исполнителя из строки заголовка или имени файла
  static Map<String, String> parseArtistAndTitle(String rawTitle, {String fallbackArtist = 'VideoToMp3'}) {
    var clean = rawTitle
        .replaceAll(RegExp(r'\.(mp4|mkv|mov|avi|webm|mp3|m4a)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[[^\]]*(official|video|audio|lyrics|hd|4k|mv)[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\([^\)]*(official|video|audio|lyrics|hd|4k|mv)[^\)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'#\S+'), '')
        .trim();

    if (clean.isEmpty) {
      return {'artist': fallbackArtist, 'title': 'Track_${DateTime.now().millisecondsSinceEpoch}'};
    }

    for (final sep in [' - ', ' – ', ' — ', ' | ']) {
      if (clean.contains(sep)) {
        final parts = clean.split(sep);
        final artist = parts.first.trim();
        final title = parts.sublist(1).join(sep).trim();
        if (artist.isNotEmpty && title.isNotEmpty) {
          return {'artist': artist, 'title': title};
        }
      }
    }
    return {'artist': fallbackArtist, 'title': clean};
  }

  /// Получает длительность медиафайла в секундах
  Future<double> getDurationSeconds(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final durStr = info?.getDuration();
      if (durStr != null) {
        return double.tryParse(durStr) ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  /// Извлекает красивый кадр из видео для обложки трека
  Future<String?> extractCoverFrame(String videoPath) async {
    try {
      final cDir = await coversDir();
      final outCover = '${cDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dur = await getDurationSeconds(videoPath);
      final seekSec = dur > 3.0 ? (dur * 0.25).clamp(1.0, 15.0) : 0.5;
      final inQ = videoPath.replaceAll('"', r'\"');

      final session = await FFmpegKit.execute(
        '-y -ss ${seekSec.toStringAsFixed(2)} -i "$inQ" -frames:v 1 -vf "scale=600:600:force_original_aspect_ratio=increase,crop=600:600" -q:v 2 "$outCover"',
      );
      if (ReturnCode.isSuccess(await session.getReturnCode()) && File(outCover).existsSync()) {
        return outCover;
      }
      // Фоллбэк на 0-ю секунду без фильтра
      final session2 = await FFmpegKit.execute(
        '-y -i "$inQ" -frames:v 1 -q:v 2 "$outCover"',
      );
      if (ReturnCode.isSuccess(await session2.getReturnCode()) && File(outCover).existsSync()) {
        return outCover;
      }
    } catch (_) {}
    return null;
  }

  /// Скачивает превью-картинку по URL для обложки
  Future<String?> downloadCoverImage(String imageUrl) async {
    try {
      final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final cDir = await coversDir();
        final rawCover = '${cDir.path}/raw_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final sqCover = '${cDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(rawCover).writeAsBytes(resp.bodyBytes);
        final session = await FFmpegKit.execute(
          '-y -i "$rawCover" -vf "scale=600:600:force_original_aspect_ratio=increase,crop=600:600" -q:v 2 "$sqCover"',
        );
        try {
          File(rawCover).deleteSync();
        } catch (_) {}
        if (ReturnCode.isSuccess(await session.getReturnCode()) && File(sqCover).existsSync()) {
          return sqCover;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Конвертирует видео/аудио в MP3 с поддержкой:
  /// - Обрезки (-ss / -to) и плавного затухания (fade)
  /// - Автоматического вшивания ID3v2.3 тегов (Title, Artist, Album)
  /// - Вшивания обложки (Cover Art APIC) прямо внутрь MP3
  Future<String?> convertToMp3(
    String inputPath, {
    int bitrateKbps = 192,
    String? title,
    String? artist,
    String? coverImagePath,
    double? trimStartSec,
    double? trimEndSec,
    bool fadeInOut = false,
  }) async {
    if (!File(inputPath).existsSync()) return null;

    await updateForegroundNotification(
      title: 'Конвертация в MP3',
      text: title ?? inputPath.split('/').last,
      progress: 50,
    );

    try {
      final outDir = await outputDir();
      final rawName = title?.trim().isNotEmpty == true ? title!.trim() : inputPath.split('/').last;
      final parsed = parseArtistAndTitle(rawName);
      final finalTitle = (title != null && title.trim().isNotEmpty) ? title.trim() : parsed['title']!;
      final finalArtist = (artist != null && artist.trim().isNotEmpty) ? artist.trim() : parsed['artist']!;

      var safeBase = finalTitle.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      if (safeBase.length > 50) safeBase = safeBase.substring(0, 50);
      if (safeBase.isEmpty) safeBase = 'track';

      final outPath = '${outDir.path}/${safeBase}_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final cover = coverImagePath ?? await extractCoverFrame(inputPath);

      final inQ = inputPath.replaceAll('"', r'\"');
      final titleEsc = finalTitle.replaceAll('"', r'\"');
      final artistEsc = finalArtist.replaceAll('"', r'\"');

      final trimArgs = StringBuffer();
      if (trimStartSec != null && trimStartSec > 0) {
        trimArgs.write('-ss ${trimStartSec.toStringAsFixed(2)} ');
      }
      if (trimEndSec != null && trimEndSec > 0 && (trimStartSec == null || trimEndSec > trimStartSec)) {
        trimArgs.write('-to ${trimEndSec.toStringAsFixed(2)} ');
      }

      String filterArg = '';
      if (fadeInOut && trimStartSec != null && trimEndSec != null && trimEndSec > trimStartSec + 3) {
        final dur = trimEndSec - trimStartSec;
        final fadeOutStart = (dur - 2.0).clamp(0.5, dur);
        filterArg = '-af "afade=t=in:st=0:d=1.5,afade=t=out:st=${fadeOutStart.toStringAsFixed(2)}:d=2.0" ';
      }

      String cmd;
      if (cover != null && File(cover).existsSync()) {
        final covQ = cover.replaceAll('"', r'\"');
        cmd = '-y ${trimArgs.toString()}-i "$inQ" -i "$covQ" '
            '-map 0:a:0 -map 1:v:0 '
            '$filterArg'
            '-c:a libmp3lame -b:a ${bitrateKbps}k '
            '-c:v mjpeg -id3v2_version 3 '
            '-metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" '
            '-metadata title="$titleEsc" -metadata artist="$artistEsc" -metadata album="VideoToMp3" '
            '"$outPath"';
      } else {
        cmd = '-y ${trimArgs.toString()}-i "$inQ" -vn '
            '$filterArg'
            '-c:a libmp3lame -b:a ${bitrateKbps}k -id3v2_version 3 '
            '-metadata title="$titleEsc" -metadata artist="$artistEsc" -metadata album="VideoToMp3" '
            '"$outPath"';
      }

      var session = await FFmpegKit.execute(cmd);
      var rc = await session.getReturnCode();

      // Если с обложкой не вышло (например, входной файл — чистое аудио с нестандартным потоком), пробуем без обложки
      if (!ReturnCode.isSuccess(rc) || !File(outPath).existsSync()) {
        final fallbackCmd = '-y ${trimArgs.toString()}-i "$inQ" -vn '
            '$filterArg'
            '-c:a libmp3lame -b:a ${bitrateKbps}k -id3v2_version 3 '
            '-metadata title="$titleEsc" -metadata artist="$artistEsc" '
            '"$outPath"';
        session = await FFmpegKit.execute(fallbackCmd);
        rc = await session.getReturnCode();
      }

      if (ReturnCode.isSuccess(rc) && File(outPath).existsSync()) {
        return outPath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Обрезает существующий MP3 или видео и создаёт новый MP3 (и опционально ставит на рингтон)
  Future<String?> trimAudioToMp3({
    required String inputPath,
    required double startSec,
    required double endSec,
    int bitrateKbps = 192,
    String? title,
    String? artist,
    String? coverPath,
    bool fadeInOut = true,
  }) async {
    return convertToMp3(
      inputPath,
      bitrateKbps: bitrateKbps,
      title: title,
      artist: artist,
      coverImagePath: coverPath,
      trimStartSec: startSec,
      trimEndSec: endSec,
      fadeInOut: fadeInOut,
    );
  }

  /// Скачивание и конвертация по ссылке (YouTube, TikTok без водяного знака, Instagram)
  /// Использует:
  /// 1) Нативный движок DownloadForegroundService (youtubedl-android 0.18.1 + TikWM HD API без водяного знака)
  /// 2) Фоллбэк в Dart через TikWM API (для TikTok) и YoutubeExplode (для YouTube)
  Future<DownloadResult?> downloadFromUrl(
    String url, {
    required String mode, // 'mp3' или 'video'
    int bitrateKbps = 192,
    double? trimStartSec,
    double? trimEndSec,
    void Function(double progress, String status)? onProgress,
  }) async {
    final cleanUrl = extractFirstUrl(url) ?? url.trim();
    final platform = detectPlatform(cleanUrl);
    onProgress?.call(0.05, 'Анализ ссылки ($platform)...');

    // 1. Если это TikTok — сначала пробуем прямой TikWM API (гарантированно без водяного знака в HD)
    if (platform == 'tiktok') {
      final tikResult = await _downloadTikTokNoWatermark(
        cleanUrl,
        mode: mode,
        bitrateKbps: bitrateKbps,
        trimStartSec: trimStartSec,
        trimEndSec: trimEndSec,
        onProgress: onProgress,
      );
      if (tikResult != null) return tikResult;
    }

    // 2. Вызываем нативный движок yt-dlp (youtubedl-android 0.18.1) через MethodChannel
    try {
      onProgress?.call(0.15, 'Загрузка через встроенный движок yt-dlp...');
      final targetDir = mode == 'video' ? (await videoDir()).path : (await outputDir()).path;
      final res = await mediaChannel.invokeMapMethod<String, dynamic>('downloadUrlNative', {
        'url': cleanUrl,
        'mode': mode,
        'bitrate': bitrateKbps,
        'outputDir': targetDir,
      });

      if (res != null && res['filePath'] != null) {
        final rawFile = res['filePath'] as String;
        final rawTitle = (res['title'] ?? 'Video') as String;
        final rawArtist = (res['uploader'] ?? 'Author') as String;
        final thumbUrl = res['thumbnail'] as String?;

        if (File(rawFile).existsSync()) {
          String? coverPath;
          if (thumbUrl != null && thumbUrl.startsWith('http')) {
            coverPath = await downloadCoverImage(thumbUrl);
          }
          coverPath ??= await extractCoverFrame(rawFile);

          if (mode == 'mp3') {
            onProgress?.call(0.80, 'Упаковка MP3, тегов ID3 и обложки...');
            final mp3Path = await convertToMp3(
              rawFile,
              bitrateKbps: bitrateKbps,
              title: rawTitle,
              artist: rawArtist,
              coverImagePath: coverPath,
              trimStartSec: trimStartSec,
              trimEndSec: trimEndSec,
            );
            if (mp3Path != null) {
              if (rawFile != mp3Path) {
                try {
                  File(rawFile).deleteSync();
                } catch (_) {}
              }
              await saveToMusic(mp3Path);
              onProgress?.call(1.0, 'Готово!');
              return DownloadResult(
                filePath: mp3Path,
                title: rawTitle,
                artist: rawArtist,
                coverPath: coverPath,
                isVideo: false,
                platform: platform,
              );
            }
          } else {
            await saveToMovies(rawFile);
            onProgress?.call(1.0, 'Видео сохранено!');
            return DownloadResult(
              filePath: rawFile,
              title: rawTitle,
              artist: rawArtist,
              coverPath: coverPath,
              isVideo: true,
              platform: platform,
            );
          }
        }
      }
    } catch (_) {}

    // 3. Фоллбэк для YouTube через youtube_explode_dart
    if (platform == 'youtube') {
      final ytRes = await _downloadYouTubeFallback(
        cleanUrl,
        mode: mode,
        bitrateKbps: bitrateKbps,
        trimStartSec: trimStartSec,
        trimEndSec: trimEndSec,
        onProgress: onProgress,
      );
      if (ytRes != null) return ytRes;
    }

    return null;
  }

  /// Прямое скачивание TikTok БЕЗ водяного знака через TikWM API
  Future<DownloadResult?> _downloadTikTokNoWatermark(
    String url, {
    required String mode,
    required int bitrateKbps,
    double? trimStartSec,
    double? trimEndSec,
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.12, 'TikTok: получение оригинала без водяного знака...');
      final apiUri = Uri.parse('https://www.tikwm.com/api/');
      final resp = await http.post(
        apiUri,
        body: {'url': url, 'hd': '1'},
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 0 || data['data'] == null) return null;

      final info = data['data'] as Map<String, dynamic>;
      final playUrl = (info['hdplay'] ?? info['play']) as String?;
      if (playUrl == null || playUrl.isEmpty) return null;

      final resolvedVideoUrl = playUrl.startsWith('http') ? playUrl : 'https://www.tikwm.com$playUrl';
      final rawTitle = (info['title'] ?? 'TikTok_${DateTime.now().millisecondsSinceEpoch}').toString();
      final authorObj = info['author'] as Map<String, dynamic>?;
      final artist = (authorObj?['nickname'] ?? authorObj?['unique_id'] ?? 'TikTok').toString();
      final coverUrl = (info['origin_cover'] ?? info['cover'])?.toString();

      final vDir = await videoDir();
      var safeName = rawTitle.replaceAll(RegExp(r'[\\/:*?"<>|#\s]+'), '_');
      if (safeName.length > 40) safeName = safeName.substring(0, 40);
      if (safeName.isEmpty) safeName = 'tiktok_video';
      final tempVideoPath = '${vDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      onProgress?.call(0.30, 'Скачивание видео без водяного знака...');
      final ok = await _downloadFileWithProgress(
        resolvedVideoUrl,
        tempVideoPath,
        onProgress: (p) => onProgress?.call(0.30 + p * 0.45, 'Скачивание: ${(p * 100).toInt()}%'),
      );
      if (!ok || !File(tempVideoPath).existsSync()) return null;

      String? coverPath;
      if (coverUrl != null && coverUrl.startsWith('http')) {
        coverPath = await downloadCoverImage(coverUrl);
      }
      coverPath ??= await extractCoverFrame(tempVideoPath);

      if (mode == 'video') {
        await saveToMovies(tempVideoPath);
        onProgress?.call(1.0, 'Видео без знака готово!');
        return DownloadResult(
          filePath: tempVideoPath,
          title: rawTitle,
          artist: artist,
          coverPath: coverPath,
          isVideo: true,
          platform: 'tiktok',
        );
      } else {
        onProgress?.call(0.80, 'Конвертация в MP3 + обложка и теги...');
        final mp3Path = await convertToMp3(
          tempVideoPath,
          bitrateKbps: bitrateKbps,
          title: rawTitle,
          artist: artist,
          coverImagePath: coverPath,
          trimStartSec: trimStartSec,
          trimEndSec: trimEndSec,
        );
        try {
          File(tempVideoPath).deleteSync();
        } catch (_) {}
        if (mp3Path == null) return null;
        await saveToMusic(mp3Path);
        onProgress?.call(1.0, 'MP3 готов!');
        return DownloadResult(
          filePath: mp3Path,
          title: rawTitle,
          artist: artist,
          coverPath: coverPath,
          isVideo: false,
          platform: 'tiktok',
        );
      }
    } catch (_) {
      return null;
    }
  }

  /// Фоллбэк для YouTube через youtube_explode_dart
  Future<DownloadResult?> _downloadYouTubeFallback(
    String url, {
    required String mode,
    required int bitrateKbps,
    double? trimStartSec,
    double? trimEndSec,
    void Function(double progress, String status)? onProgress,
  }) async {
    final yt = YoutubeExplode();
    try {
      onProgress?.call(0.20, 'YouTube: получение потоков...');
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);

      final parsed = parseArtistAndTitle(video.title, fallbackArtist: video.author);
      final title = parsed['title']!;
      final artist = parsed['artist']!;
      final coverPath = await downloadCoverImage(video.thumbnails.highResUrl);

      final vDir = await videoDir();
      var safeName = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      if (safeName.length > 40) safeName = safeName.substring(0, 40);
      if (safeName.isEmpty) safeName = 'youtube';

      if (mode == 'video') {
        final muxed = manifest.muxed.withHighestBitrate();
        final outVideo = '${vDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final stream = yt.videos.streamsClient.get(muxed);
        final file = File(outVideo);
        final sink = file.openWrite();
        final total = muxed.size.totalBytes;
        var received = 0;
        await for (final chunk in stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call(0.25 + (received / total) * 0.70, 'Загрузка видео: ${(received * 100 ~/ total)}%');
          }
        }
        await sink.close();
        await saveToMovies(outVideo);
        onProgress?.call(1.0, 'Видео готово!');
        return DownloadResult(
          filePath: outVideo,
          title: title,
          artist: artist,
          coverPath: coverPath,
          isVideo: true,
          platform: 'youtube',
        );
      } else {
        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        final tempAudio = '${vDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final stream = yt.videos.streamsClient.get(audioStreamInfo);
        final file = File(tempAudio);
        final sink = file.openWrite();
        final total = audioStreamInfo.size.totalBytes;
        var received = 0;
        await for (final chunk in stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call(0.20 + (received / total) * 0.55, 'Загрузка аудио: ${(received * 100 ~/ total)}%');
          }
        }
        await sink.close();

        onProgress?.call(0.80, 'Конвертация в MP3 + вшивание обложки...');
        final mp3Path = await convertToMp3(
          tempAudio,
          bitrateKbps: bitrateKbps,
          title: title,
          artist: artist,
          coverImagePath: coverPath,
          trimStartSec: trimStartSec,
          trimEndSec: trimEndSec,
        );
        try {
          File(tempAudio).deleteSync();
        } catch (_) {}
        if (mp3Path == null) return null;
        await saveToMusic(mp3Path);
        onProgress?.call(1.0, 'MP3 готов!');
        return DownloadResult(
          filePath: mp3Path,
          title: title,
          artist: artist,
          coverPath: coverPath,
          isVideo: false,
          platform: 'youtube',
        );
      }
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  Future<bool> _downloadFileWithProgress(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] =
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
      final resp = await client.send(req).timeout(const Duration(seconds: 45));
      if (resp.statusCode >= 400) return false;
      final total = resp.contentLength ?? 0;
      var received = 0;
      final file = File(savePath);
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.close();
      return file.existsSync() && file.lengthSync() > 1024;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static String? extractFirstUrl(String text) {
    final match = RegExp(r'https?://[^\s"<>]+').firstMatch(text);
    return match?.group(0);
  }

  static List<String> extractAllUrls(String text) {
    return RegExp(r'https?://[^\s"<>]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
  }

  /// Сохраняет MP3 в общую папку «Музыка/VideoToMp3»
  Future<bool> saveToMusic(String path) async {
    try {
      final r = await mediaChannel.invokeMethod<String>('saveToMusic', {
        'path': path,
        'name': path.split('/').last,
      });
      return r != null;
    } catch (_) {
      return false;
    }
  }

  /// Сохраняет видео в общую папку «Фильмы/VideoToMp3» (Галерея)
  Future<bool> saveToMovies(String path) async {
    try {
      final r = await mediaChannel.invokeMethod<String>('saveToMovies', {
        'path': path,
        'name': path.split('/').last,
      });
      return r != null;
    } catch (_) {
      return false;
    }
  }

  /// Устанавливает MP3 как системный рингтон телефона
  Future<bool> setAsRingtone(String path, String title) async {
    try {
      final ok = await mediaChannel.invokeMethod<bool>('setRingtone', {
        'path': path,
        'title': title,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Обновляет прогресс в шторке уведомлений
  Future<void> updateForegroundNotification({
    required String title,
    required String text,
    required int progress,
  }) async {
    try {
      await mediaChannel.invokeMethod('showProgressNotification', {
        'title': title,
        'text': text,
        'progress': progress,
      });
    } catch (_) {}
  }

  /// Показывает уведомление «Готово» с открытием файла/плеера по нажатию
  Future<void> showCompletedNotification({
    required String title,
    required String filePath,
    required bool isVideo,
  }) async {
    try {
      await mediaChannel.invokeMethod('showCompletedNotification', {
        'title': title,
        'filePath': filePath,
        'isVideo': isVideo,
      });
    } catch (_) {}
  }
}
