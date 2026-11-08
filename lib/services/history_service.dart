import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversion_item.dart';

/// Увеличивается при любом изменении истории — экраны слушают и обновляются сами.
final ValueNotifier<int> historyChanged = ValueNotifier<int>(0);

class HistoryService {
  static const _key = 'conversion_history';

  Future<List<ConversionItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <ConversionItem>[];
    for (final e in prefs.getStringList(_key) ?? <String>[]) {
      try {
        out.add(ConversionItem.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> add(ConversionItem item) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList(_key) ?? <String>[];
    l.add(jsonEncode(item.toJson()));
    await p.setStringList(_key, l);
    historyChanged.value++;
  }

  Future<void> removeByPath(String path) async {
    final p = await SharedPreferences.getInstance();
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
    historyChanged.value++;
  }
}
