import 'dart:convert';
import 'package:http/http.dart' as http;

class WebPriceOffer {
  final String title;
  final String priceText;
  final double? numericPrice;
  final String sourceUrl;
  final String snippet;

  const WebPriceOffer({
    required this.title,
    required this.priceText,
    this.numericPrice,
    required this.sourceUrl,
    required this.snippet,
  });
}

class WebResearchService {
  static final WebResearchService instance = WebResearchService._();
  WebResearchService._();

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8',
  };

  /// Свободный поиск информации в интернете без браузера (DuckDuckGo HTML + прямая выжимка текста)
  Future<String> searchInternetFree(String query, {int maxResults = 6}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return 'Пустой поисковый запрос';

    final results = <String>[];
    try {
      final url = Uri.parse(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(cleanQuery)}',
      );
      final resp = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
        final blockRegex = RegExp(
          r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/a>',
          caseSensitive: false,
        );
        final matches = blockRegex.allMatches(html).take(maxResults);
        var idx = 1;
        for (final m in matches) {
          final rawHref = _cleanHtml(m.group(1) ?? '');
          final title = _cleanHtml(m.group(2) ?? '');
          final snippet = _cleanHtml(m.group(3) ?? '');
          results.add('$idx. $title\n   Описание: $snippet\n   Ссылка: $rawHref');
          idx++;
        }
      }
    } catch (_) {}

    if (results.isEmpty) {
      try {
        final wikiUrl = Uri.parse(
          'https://ru.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeQueryComponent(cleanQuery)}&utf8=&format=json',
        );
        final wikiResp = await http.get(wikiUrl, headers: _headers).timeout(const Duration(seconds: 12));
        if (wikiResp.statusCode == 200) {
          final map = jsonDecode(utf8.decode(wikiResp.bodyBytes)) as Map<String, dynamic>;
          final list = (map['query']?['search'] as List?) ?? const [];
          for (var i = 0; i < list.length && i < maxResults; i++) {
            final item = list[i] as Map<String, dynamic>;
            final t = _cleanHtml((item['title'] ?? '').toString());
            final s = _cleanHtml((item['snippet'] ?? '').toString());
            results.add('${i + 1}. $t — $s');
          }
        }
      } catch (e) {
        return 'Ошибка веб-поиска: $e';
      }
    }

    if (results.isEmpty) {
      return 'По запросу "$cleanQuery" прямых текстовых сниппетов не найдено.';
    }
    return '🌐 РЕЗУЛЬТАТЫ СВОБОДНОГО ПОИСКА В ИНТЕРНЕТЕ ПО ЗАПРОСУ "$cleanQuery":\n${results.join('\n\n')}';
  }

  /// Чтение и очистка любой веб-страницы для глубокого изучения ИИ
  Future<String> fetchWebpageText(String urlStr, {int maxChars = 4000}) async {
    final normalized = urlStr.startsWith('http') ? urlStr : 'https://$urlStr';
    try {
      final resp = await http
          .get(Uri.parse(normalized), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return 'Страница вернула HTTP ${resp.statusCode}';
      }
      var text = utf8.decode(resp.bodyBytes, allowMalformed: true);
      text = text.replaceAll(RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false), ' ');
      text = text.replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), ' ');
      text = _cleanHtml(text);
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars)}...';
      }
      return '📄 Содержимое страницы $normalized:\n$text';
    } catch (e) {
      return 'Не удалось загрузить страницу $normalized: $e';
    }
  }

  /// Поиск и сравнение цен в интернете (находит самые дешёвые и выгодные предложения)
  Future<String> comparePricesOnline(String itemOrService) async {
    final query = '$itemOrService цена стоимость прайс купить записаться дешево';
    final rawSearch = await searchInternetFree(query, maxResults: 8);
    final priceRegex = RegExp(
      r'(\d[\d\s]{1,7})\s*(сом|сомони|сомон|с\.|руб|₽|тг|тенге|\$|usd)',
      caseSensitive: false,
    );

    final extractedPrices = <String>[];
    for (final line in rawSearch.split('\n')) {
      final m = priceRegex.firstMatch(line);
      if (m != null) {
        extractedPrices.add('• Найдено предложение: ${m.group(0)} — ${line.trim()}');
      }
    }

    final sb = StringBuilder();
    sb.writeln('🏷️ СРАВНЕНИЕ ЦЕН И УСЛУГ ПО ЗАПРОСУ: "$itemOrService"');
    if (extractedPrices.isNotEmpty) {
      sb.writeln('Найденные ценовые предложения:');
      for (final p in extractedPrices) {
        sb.writeln(p);
      }
      sb.writeln('');
    }
    sb.writeln(rawSearch);
    return sb.toString().trim();
  }

  String _cleanHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class StringBuilder {
  final StringBuffer _buf = StringBuffer();
  void writeln([String s = '']) => _buf.writeln(s);
  @override
  String toString() => _buf.toString();
}
