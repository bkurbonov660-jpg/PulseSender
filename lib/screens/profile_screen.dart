import 'dart:io';
import 'package:flutter/material.dart';
import '../services/converter_service.dart';
import '../services/history_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _h = HistoryService();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _upd();
    historyChanged.addListener(_onChanged);
  }

  void _onChanged() => _upd();

  @override
  void dispose() {
    historyChanged.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _upd() async {
    final l = await _h.load();
    if (mounted) setState(() => _count = l.length);
  }

  Future<void> _updateYtDlp() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Проверка обновлений движка yt-dlp...')),
    );
    try {
      final res = await ConverterService.mediaChannel.invokeMethod<String>('updateYtDlp');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Статус обновления yt-dlp: ${res ?? "OK"}')),
        );
      }
    } catch (_) {}
  }

  Future<void> _clear() async {
    await _h.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История очищена (файлы сохранены)')),
      );
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить все файлы внутри приложения?'),
        content: const Text('Внутренний кэш MP3 и видео будет очищен.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final d in [await ConverterService.outputDir(), await ConverterService.videoDir()]) {
        for (final e in d.listSync()) {
          if (e is File) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    await _h.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки и Движок')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, size: 32, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VideoToMp3 v2.0 Pro',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Обработано файлов: $_count',
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_alt_rounded, color: Color(0xFF10B981)),
                  title: const Text('Обновить ядро экстрактора (yt-dlp)'),
                  subtitle: const Text('Поддержка новых алгоритмов YouTube, TikTok и Instagram'),
                  onTap: _updateYtDlp,
                ),
                const Divider(height: 1, color: Color(0xFF2A303C)),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Color(0xFF10B981)),
                  title: const Text('Как пользоваться мини-окошком?'),
                  subtitle: const Text('В TikTok / YouTube / Reels нажмите «Поделиться» → «Ещё» → VideoToMp3'),
                ),
                const Divider(height: 1, color: Color(0xFF2A303C)),
                ListTile(
                  leading: const Icon(Icons.history_rounded, color: Colors.amber),
                  title: const Text('Очистить историю списка'),
                  subtitle: const Text('Сами MP3 и видео останутся в памяти'),
                  onTap: _clear,
                ),
                const Divider(height: 1, color: Color(0xFF2A303C)),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: const Text('Очистить внутреннюю папку приложения'),
                  subtitle: const Text('Удалить кэшированные копии'),
                  onTap: _deleteAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
