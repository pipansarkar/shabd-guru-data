// Daily Editorial Words: picks 10 exam-worthy words from today's newspaper
// editorials and writes our own cards for them.
//
//   GEMINI_API_KEY=... dart run editorial.dart
//
// Legal: only each article's headline and link are published (so users can
// read it on the paper's site). Editorial text is never copied: the feeds'
// one-line summaries are only used to choose words, and every meaning,
// translation and example sentence is newly written.
//
// editorial.json keeps the last 30 days (newest first); every day is also
// archived in archive/editorial-YYYY-MM.json.
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

const perDay = 10;
const keepDays = 30;

/// Editorial RSS feeds (headline, link, one-line summary).
const feeds = {
  'The Hindu': 'https://www.thehindu.com/opinion/editorial/feeder/default.rss',
  'The Indian Express':
      'https://indianexpress.com/section/opinion/editorials/feed/',
  'Hindustan Times':
      'https://www.hindustantimes.com/feeds/rss/editorials/rssfeed.xml',
  'Mint': 'https://www.livemint.com/rss/opinion',
};

class Item {
  Item(this.paper, this.title, this.summary, this.url, this.published);
  final String paper, title, summary, url;
  final DateTime? published;
  String get text => '$title. $summary';
}

Future<void> main() async {
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set');
    exit(1);
  }
  final file = File('editorial.json');
  final data = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'version': 0, 'days': <Object>[]};
  final days = (data['days'] as List).cast<Map<String, dynamic>>();
  final today = todayIst();
  if (days.isNotEmpty && days.first['date'] == today) {
    stdout.writeln('Editorial words for $today already published.');
    return;
  }

  // 1. Today's editorials.
  final now = DateTime.now().toUtc();
  final items = <Item>[];
  for (final f in feeds.entries) {
    final got = await readFeed(f.key, f.value);
    final fresh = got.where(
      (i) => i.published == null || now.difference(i.published!).inHours < 36,
    );
    stdout.writeln('${f.key}: ${got.length} items, ${fresh.length} recent');
    items.addAll(fresh.take(8));
  }
  if (items.isEmpty) {
    stdout.writeln('No recent editorials found; no changes.');
    return;
  }

  // 2. Choose words. Skip ones used in the last 30 days.
  final recent = {
    for (final d in days)
      for (final w in d['words'] as List) (w as Map)['id'] as String,
  };
  final ai = Gemini(await pickModels());
  final listing = [
    for (var i = 0; i < items.length; i++)
      '[$i] ${items[i].title} — ${items[i].summary}',
  ].join('\n');
  final picked = await ai.json(
    '''
These are today's newspaper editorial headlines and one-line summaries:
$listing

Pick ${perDay + 6} English words that an Indian Bank PO, SSC CGL or UPSC
aspirant should learn: advanced, exam-worthy vocabulary that appears in an
item above (not names, places, party names, abbreviations or very common
words). Spread them across different items. Give each word in its base
dictionary form (e.g. "deplore" for "deplored") and the [index] of the item
it appears in.
Do not choose any of: ${recent.join(', ')}.''',
    schema: {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'word': {'type': 'STRING'},
          'item': {'type': 'INTEGER'},
        },
        'required': ['word', 'item'],
      },
    },
  );
  final chosen = <String, Item>{};
  for (final p in (picked as List).cast<Map<String, dynamic>>()) {
    final w = (p['word'] as String? ?? '').trim().toLowerCase();
    final i = (p['item'] as num?)?.toInt() ?? -1;
    if (!RegExp(r'^[a-z]{4,}$').hasMatch(w) || i < 0 || i >= items.length) {
      continue;
    }
    if (recent.contains(w) || chosen.containsKey(w)) continue;
    // The word (or an inflection) must really appear in that item.
    final stem = w.substring(0, (w.length - 2).clamp(4, w.length));
    if (!items[i].text.toLowerCase().contains(stem)) continue;
    chosen[w] = items[i];
  }
  stdout.writeln('Chosen: ${chosen.keys.join(', ')}');

  // 3. Write cards (in the sense used in the editorial).
  final cards = <Map<String, dynamic>>[];
  final words = chosen.keys.toList();
  for (var i = 0; i < words.length && cards.length < perDay; i += 5) {
    final batch = words.skip(i).take(5).toList();
    final context = [
      'Context: these words were used in these newspaper headlines; use that sense:',
      for (final w in batch) '- $w: "${chosen[w]!.title}"',
    ].join('\n');
    try {
      for (final e in await makeCards(ai, batch, context: context)) {
        final src = chosen[e['id']]!;
        cards.add({
          ...e,
          'source': {'paper': src.paper, 'headline': src.title, 'url': src.url},
        });
        if (cards.length >= perDay) break;
      }
    } catch (e) {
      stderr.writeln('Batch $batch failed: $e');
      if ('$e'.contains('All models failed') || '$e'.contains('budget')) break;
    }
  }
  if (cards.isEmpty) {
    stdout.writeln('No valid editorial words produced; no changes.');
    return;
  }

  // 4. Publish today's set; keep 30 days live, archive everything.
  final day = {'date': today, 'words': cards};
  final next = (data['version'] as int) + 1;
  final out = {
    'version': next,
    'updated': today,
    'days': [day, ...days].take(keepDays).toList(),
  };
  final problems = checkEditorialFile(out, previous: data);
  if (problems.isNotEmpty) {
    stderr.writeln(
      'Not publishing, validation failed:\n${problems.join('\n')}',
    );
    exit(1);
  }
  file.writeAsStringSync(formatDays(out));
  final archive = File('archive/editorial-${today.substring(0, 7)}.json');
  archive.parent.createSync(recursive: true);
  final arch = archive.existsSync()
      ? jsonDecode(archive.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'version': 0, 'days': <Object>[]};
  archive.writeAsStringSync(
    formatDays({
      'version': (arch['version'] as int) + 1,
      'updated': today,
      'days': [day, ...(arch['days'] as List)],
    }),
  );
  addCommitLine(
    'Editorial words $today: ${cards.map((c) => c['word']).join(', ')}',
  );
  stdout.writeln('Published ${cards.length} editorial words for $today.');
}

/// Reads an RSS feed; returns an empty list on any failure.
Future<List<Item>> readFeed(String paper, String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; shabd-guru-data)');
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      stderr.writeln('$paper: HTTP ${res.statusCode}');
      return const [];
    }
    final xml = await res.transform(utf8.decoder).join();
    return [
      for (final m in RegExp(
        r'<item\b[^>]*>(.*?)</item>',
        dotAll: true,
      ).allMatches(xml))
        if (_item(paper, m[1]!) case final item?) item,
    ];
  } catch (e) {
    stderr.writeln('$paper: $e');
    return const [];
  } finally {
    client.close();
  }
}

Item? _item(String paper, String xml) {
  String tag(String t) {
    final m = RegExp('<$t\\b[^>]*>(.*?)</$t>', dotAll: true).firstMatch(xml);
    var v = m?[1] ?? '';
    v = v.replaceAllMapped(
      RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true),
      (c) => c[1]!,
    );
    v = v.replaceAll(RegExp(r'<[^>]+>'), ' ');
    v = v
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (c) => String.fromCharCode(int.parse(c[1]!)),
        );
    return v.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final title = tag('title');
  final link = tag('link');
  if (title.isEmpty || !link.startsWith('https://')) return null;
  var summary = tag('description');
  if (summary.length > 300) summary = '${summary.substring(0, 300)}…';
  return Item(paper, title, summary, link, parseRfc822(tag('pubDate')));
}

/// "Thu, 26 Nov 2026 00:12:32 +0530" -> UTC; null if unparseable.
DateTime? parseRfc822(String s) {
  final m = RegExp(
    r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})(?::(\d{2}))? ?([+-]\d{4}|GMT|UTC|Z)?',
  ).firstMatch(s);
  if (m == null) return null;
  const months = 'JanFebMarAprMayJunJulAugSepOctNovDec';
  final mon = months.indexOf(m[2]!) ~/ 3 + 1;
  if (mon <= 0) return null;
  var t = DateTime.utc(
    int.parse(m[3]!),
    mon,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6] ?? '0'),
  );
  final z = m[7];
  if (z != null && (z.startsWith('+') || z.startsWith('-'))) {
    final mins = int.parse(z.substring(1, 3)) * 60 + int.parse(z.substring(3));
    t = t.subtract(Duration(minutes: z.startsWith('+') ? mins : -mins));
  }
  return t;
}

/// One word per line, like words.json.
String formatDays(Map<String, dynamic> data) {
  final b = StringBuffer('{\n');
  b.writeln('  "version": ${jsonEncode(data['version'])},');
  b.writeln('  "updated": ${jsonEncode(data['updated'])},');
  b.writeln('  "days": [');
  final days = data['days'] as List;
  for (var d = 0; d < days.length; d++) {
    final day = days[d] as Map;
    b.writeln('    {"date": ${jsonEncode(day['date'])}, "words": [');
    final words = day['words'] as List;
    for (var i = 0; i < words.length; i++) {
      b.write('      ${jsonEncode(words[i])}');
      b.writeln(i == words.length - 1 ? '' : ',');
    }
    b.writeln(d == days.length - 1 ? '    ]}' : '    ]},');
  }
  b.writeln('  ]');
  b.writeln('}');
  return b.toString();
}
