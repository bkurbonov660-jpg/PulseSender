import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversion_item.dart';

final ValueNotifier<int> historyChanged = ValueNotifier<int>(0);
final ValueNotifier<String?> activePlayRequestPath = ValueNotifier<String?>(null);

class HistoryService {
  static const _key = 'conversion_history_v2';
  static const _legacyKey = 'conversion_history';

  Future<List<ConversionItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final out = <ConversionItem>[];
    final list = prefs.getStringList(_key) ?? prefs.getStringList(_legacyKey) ?? <String>[];
    for (final e in list) {
      try {
        out.add(ConversionItem.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> add(ConversionItem item) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final l = p.getStringList(_key) ?? <String>[];
    l.removeWhere((e) {
      try {
        return (jsonDecode(e) as Map<String, dynamic>)['filePath'] == item.filePath;
      } catch (_) {
        return false;
      }
    });
    l.add(jsonEncode(item.toJson()));
    await p.setStringList(_key, l);
    historyChanged.value++;
  }

  Future<void> removeByPath(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final l = (p.getStringList(_key) ?? <String>[]).where((e) {
      try {
        return (jsonDecode(e) as Map<String, dynamic>)['filePath'] != path;
      } catch (_) {
        return false;
      }
    }).toList();
    await p.setStringList(_key, l);
    historyChanged.value++;
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    await p.remove(_legacyKey);
    historyChanged.value++;
  }
}
