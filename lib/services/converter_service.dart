import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ConverterService {
  static const _media = MethodChannel('vtomp3/media');

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

  /// Копирует MP3 в общую папку «Музыка/VideoToMp3» — туда, где лежит вся музыка телефона.
  Future<bool> saveToMusic(String path) async {
    try {
      final sdk = await _media.invokeMethod<int>('sdkInt') ?? 99;
      if (sdk < 29) {
        try {
          await Permission.storage.request();
        } catch (_) {}
      }
      final r = await _media.invokeMethod<String>('saveToMusic', {
        'path': path,
        'name': path.split('/').last,
      });
      return r != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> convertToMp3(String inputPath, {int bitrateKbps = 192}) async {
    if (!File(inputPath).existsSync()) return null;
    var serviceStarted = false;
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Video→MP3',
        notificationText: 'Идёт конвертация…',
      );
      serviceStarted = true;
    } catch (_) {
      // без foreground-сервиса конвертация всё равно работает
    }
    try {
      final outDir = await outputDir();
      final fileName = inputPath.split('/').last;
      final dot = fileName.lastIndexOf('.');
      var base = dot > 0 ? fileName.substring(0, dot) : fileName;
      base = base.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      if (base.isEmpty) base = 'audio';
      final outPath = '${outDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final inQ = inputPath.replaceAll('"', r'\"');
      final session = await FFmpegKit.execute(
        '-y -i "$inQ" -vn -map_metadata 0 -acodec libmp3lame -b:a ${bitrateKbps}k "$outPath"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(outPath).existsSync()) {
        return outPath;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (serviceStarted) {
        try {
          await FlutterForegroundTask.stopService();
        } catch (_) {}
      }
    }
  }
}
