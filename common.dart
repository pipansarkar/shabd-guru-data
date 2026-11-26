// Shared by generate.dart (daily words) and editorial.dart (editorial
// words): the free Gemini client, card prompts, Datamuse checks, helpers.
import 'dart:convert';
import 'dart:io';

import 'word_check.dart';

final key = Platform.environment['GEMINI_API_KEY'] ?? '';
final preferredModel = Platform.environment['GEMINI_MODEL'] ?? '';

/// Skips word-family duplicates: "abatement" when "abate" exists,
/// "endurance" when "endure" exists (shared prefix of at least 5 letters
/// covering all but the last letter of the shorter word).
bool nearDuplicate(String w, Set<String> existing) => existing.any((e) {
  var n = 0;
  while (n < w.length && n < e.length && w[n] == e[n]) {
    n++;
  }
  final shorter = w.length < e.length ? w.length : e.length;
  return n >= 5 && n >= shorter - 1;
});

const entriesSchema = {
  'type': 'ARRAY',
  'items': {
    'type': 'OBJECT',
    'properties': {
      'word': {'type': 'STRING'},
      'pos': {
        'type': 'STRING',
        'enum': ['noun', 'verb', 'adjective', 'adverb'],
      },
      'en': {'type': 'STRING'},
      'bn': {'type': 'STRING'},
      'hi': {'type': 'STRING'},
      'syn': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'ant': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'ex': {'type': 'STRING'},
      'trick': {'type': 'STRING'},
      'exams': {
        'type': 'ARRAY',
        'items': {
          'type': 'STRING',
          'enum': ['bank', 'ssc', 'cat', 'cuet', 'upsc'],
        },
      },
    },
    'required': [
      'word',
      'pos',
      'en',
      'bn',
      'hi',
      'syn',
      'ant',
      'ex',
      'trick',
      'exams',
    ],
  },
};

String writePrompt(List<String> batch, {String context = ''}) =>
    '''
Write vocabulary cards for Indian exam aspirants (Bank, SSC, CAT, CUET) for
exactly these words: ${batch.join(', ')}.
$context
For each word, in the sense most often tested in exams (or, if a context is
given above, the sense used there):
- word: the word, lower case
- pos: noun, verb, adjective or adverb
- en: a short plain-English meaning, under 12 words, in your own words
- bn: 1-3 short natural Bengali equivalents, comma-separated, Bengali
  script only, each 1-3 words, the same part of speech as the English word
  (an adjective's Bengali must be an adjective), no "বা" phrases, and
  adding nothing beyond the English meaning
- hi: the same rules in Hindi (Devanagari only, no "या" phrases)
- syn: 3-4 synonyms, same part of speech, each able to replace the word
- ant: 2-3 true antonyms, same part of speech (never overlapping syn)
- ex: one original sentence (max 20 words) that uses the word itself;
  Indian everyday context is welcome; nothing political, offensive or about
  real living people
- trick: a short memory trick (word root, sound-alike or picture) that is
  not misleading about spelling or meaning
- exams: which of bank, ssc, cat, cuet, upsc the word suits
All text must be original: do not copy definitions or examples from any
dictionary (Oxford, Merriam-Webster, Cambridge) or exam-prep book.''';

String reviewPrompt(String draft) => '''
You are a strict reviewer: a native Bengali speaker, a native Hindi speaker
and an English teacher preparing students for Indian Bank/SSC/CAT exams.
Nobody else will check these cards before students see them.
Review each card below and return the corrected cards (same fields, same
words, same order). Fix anything that is wrong:
- bn must be what a Bengali speaker actually says for this sense, spelt
  correctly in Bengali script; not Hindi written in Bengali script.
- bn and hi must mean exactly the English meaning: nothing narrower or
  extra (e.g. don't turn "shockingly bad" into "a serious crime"), nothing
  that only fits a different sense (e.g. "irritable" for "fastidious"), the
  same part of speech, 1-3 short comma-separated equivalents, no "বা"/"या".
- hi must be natural, correctly spelt Hindi in Devanagari.
- If unsure of a translation, replace it with a simpler one you are sure of.
- Every synonym must fit in the example sentence in place of the word;
  every antonym must be a true opposite; all in the same part of speech; no
  word in both lists; never the word itself.
- The example must use the word correctly.
- The meaning must be accurate and under 12 words.
- The trick must not be misleading.
Cards:
$draft''';

/// Fills `id`, trims and lower-cases list items.
Map<String, dynamic> normalise(Map<String, dynamic> e) {
  final word = (e['word'] as String? ?? '').trim().toLowerCase();
  List<String> list(String k) => [
    for (final s in (e[k] as List? ?? const []))
      if (s is String && s.trim().isNotEmpty) s.trim().toLowerCase(),
  ];
  String str(String k) => (e[k] as String? ?? '').trim();
  return {
    'id': word.replaceAll(' ', '-'),
    'word': word,
    'pos': str('pos'),
    'en': str('en'),
    'bn': str('bn'),
    'hi': str('hi'),
    'syn': list('syn').where((s) => s != word).toList(),
    'ant': list('ant').where((s) => s != word).toList(),
    'ex': str('ex'),
    'trick': str('trick'),
    'exams': list('exams'),
  };
}

/// One entry per line, like the hand-written file.
String formatWords(Map<String, dynamic> data) {
  final b = StringBuffer('{\n');
  for (final e in data.entries.where((e) => e.key != 'words')) {
    b.writeln('  ${jsonEncode(e.key)}: ${jsonEncode(e.value)},');
  }
  b.writeln('  "words": [');
  final words = data['words'] as List;
  for (var i = 0; i < words.length; i++) {
    b.write('    ${jsonEncode(words[i])}');
    b.writeln(i == words.length - 1 ? '' : ',');
  }
  b.writeln('  ]');
  b.writeln('}');
  return b.toString();
}

/// Free-tier Gemini models able to generate text, best first. GEMINI_MODEL
/// (a repo variable) goes first when set. Model names change over time, so
/// they are discovered at run time rather than hard-coded.
Future<List<String>> pickModels() async {
  final res = await request('GET', 'models?pageSize=200');
  final all = [
    for (final m in (res['models'] as List? ?? const []))
      if (((m as Map)['supportedGenerationMethods'] as List? ?? const [])
          .contains('generateContent'))
        (m['name'] as String).replaceFirst('models/', ''),
  ];
  bool textFlash(String n) =>
      n.startsWith('gemini-') &&
      n.contains('flash') &&
      !RegExp(
        r'image|tts|audio|live|embedding|thinking-exp|omni|latest',
      ).hasMatch(n);
  double ver(String n) =>
      double.tryParse(
        RegExp(r'gemini-(\d+(\.\d+)?)').firstMatch(n)?[1] ?? '',
      ) ??
      0;
  int rank(String n) =>
      (n.contains('lite') ? 2 : 0) + (n.contains('preview') ? 1 : 0);
  final flash = all.where(textFlash).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : ver(b).compareTo(ver(a));
    });
  return [
    if (preferredModel.isNotEmpty) preferredModel,
    ...flash.where((m) => m != preferredModel).take(10),
  ];
}

Future<Map<String, dynamic>> request(
  String method,
  String path, [
  Object? body,
]) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/$path'),
    );
    req.headers.set('x-goog-api-key', key);
    req.headers.set('Api-Revision', '2026-05-20');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    // A slow model must not stall the whole job.
    const limit = Duration(seconds: 90);
    final res = await req.close().timeout(limit);
    final text = await res.transform(utf8.decoder).join().timeout(limit);
    if (res.statusCode != 200) {
      throw HttpException(
        '${res.statusCode}: ${text.substring(0, text.length.clamp(0, 300))}',
      );
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

class Gemini {
  Gemini(this.models);
  final List<String> models;

  /// Models that hit their free daily limit this run; skipped from then on.
  final Set<String> _exhausted = {};

  /// Hard cap per run so the free daily quota (about 20 requests per model)
  /// is never exceeded by retries.
  int _budget = 16;

  /// Each job stops asking after this long and publishes what passed.
  static const deadline = Duration(minutes: 8);
  final _clock = Stopwatch()..start();

  /// Asks for JSON matching [schema] through the Interactions API, falling
  /// back to the next model when one is rate-limited or unavailable.
  Future<Object?> json(
    String prompt, {
    required Map<String, Object> schema,
  }) async {
    Object? lastError;
    for (final model in models) {
      if (_exhausted.contains(model)) continue;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_budget-- <= 0) throw StateError('Request budget used up');
        if (_clock.elapsed > deadline) {
          throw StateError('Time budget used up');
        }
        // Stay well under free-tier requests-per-minute.
        await Future<void>.delayed(const Duration(seconds: 6));
        try {
          final res = await request('POST', 'interactions', {
            'model': model,
            'input': prompt,
            'store': false,
            'response_format': {
              'type': 'text',
              'mime_type': 'application/json',
              'schema': lowerSchema(schema),
            },
          });
          return jsonDecode(stripFences(outputText(res)));
        } catch (e) {
          lastError = e;
          final msg = '$e';
          stderr.writeln(
            '  $model: ${msg.substring(0, msg.length.clamp(0, 300))}',
          );
          if (msg.contains('HttpException: 5') && attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 20));
            continue; // one retry on server errors
          }
          if (msg.contains('HttpException: 429') ||
              msg.contains('HttpException: 404') ||
              msg.contains('HttpException: 403')) {
            _exhausted.add(model);
          }
          break; // next model
        }
      }
    }
    throw StateError('All models failed: $lastError');
  }
}

/// Text of the model's answer: steps[type=model_output].content[type=text].
String outputText(Map<String, dynamic> res) {
  final b = StringBuffer();
  for (final step in (res['steps'] as List? ?? const [])) {
    if (step is! Map || step['type'] != 'model_output') continue;
    for (final c in (step['content'] as List? ?? const [])) {
      if (c is Map && c['type'] == 'text') b.write(c['text'] ?? '');
    }
  }
  if (b.isEmpty) throw FormatException('no model_output text in response');
  return b.toString();
}

String stripFences(String s) => s
    .trim()
    .replaceFirst(RegExp(r'^```(json)?\s*'), '')
    .replaceFirst(RegExp(r'\s*```$'), '');

/// JSON Schema with lower-case types ("ARRAY" -> "array").
Object lowerSchema(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        e.key: e.key == 'type'
            ? (e.value as String).toLowerCase()
            : lowerSchema(e.value),
    };
  }
  if (v is List) return [for (final x in v) lowerSchema(x)];
  return v as Object;
}

/// Writes cards for [batch] (draft, then reviewer pass), keeps only entries
/// that pass [checkWordEntry] after the Datamuse relation check.
Future<List<Map<String, dynamic>>> makeCards(
  Gemini ai,
  List<String> batch, {
  String context = '',
}) async {
  final draft = await ai.json(
    writePrompt(batch, context: context),
    schema: entriesSchema,
  );
  final reviewed = await ai.json(
    reviewPrompt(jsonEncode(draft)),
    schema: entriesSchema,
  );
  final out = <Map<String, dynamic>>[];
  for (final raw in reviewed as List) {
    if (raw is! Map<String, dynamic>) continue;
    final e = await datamuse.checkRelations(normalise(raw));
    final id = e['id'] as String;
    if (!batch.contains(id)) continue;
    final problems = [
      ...checkWordEntry(e),
      if ((e['syn'] as List).length < 2) 'fewer than 2 verified synonyms',
    ];
    if (problems.isNotEmpty) {
      stdout.writeln('  dropped $id: ${problems.join('; ')}');
      continue;
    }
    out.add(e);
  }
  return out;
}

final datamuse = Datamuse();

/// Free English word data (https://www.datamuse.com/api/), used to check
/// the AI's synonyms/antonyms and to rank candidate words by frequency.
/// If the service is unreachable, checks are skipped rather than failing.
/// (From 1 Feb 2027 Datamuse needs a free API key: set DATAMUSE_API_KEY.)
class Datamuse {
  final _apiKey = Platform.environment['DATAMUSE_API_KEY'] ?? '';
  bool _down = false;

  Future<List<Map<String, dynamic>>?> _get(String query) async {
    if (_down) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final q = _apiKey.isEmpty ? query : '$query&key=$_apiKey';
      final req = await client.getUrl(
        Uri.parse('https://api.datamuse.com/words?$q'),
      );
      req.headers.set('User-Agent', 'shabd-guru-data (github actions)');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      stderr.writeln('  Datamuse unavailable, skipping checks: $e');
      _down = true;
      return null;
    } finally {
      client.close();
    }
  }

  Future<Set<String>?> _words(String query) async {
    final r = await _get(query);
    return r == null
        ? null
        : {for (final w in r) (w['word'] as String).toLowerCase()};
  }

  /// Occurrences per million words (Google Books Ngrams), or null.
  Future<double?> frequency(String word) async {
    final r = await _get('sp=${Uri.encodeQueryComponent(word)}&md=f&max=1');
    if (r == null || r.isEmpty || r.first['word'] != word)
      return r == null ? null : 0;
    for (final t in (r.first['tags'] as List? ?? const [])) {
      if (t is String && t.startsWith('f:'))
        return double.tryParse(t.substring(2));
    }
    return 0;
  }

  /// Keeps synonyms Datamuse knows are related to the word (and not listed
  /// as its antonyms); drops antonyms it lists as synonyms.
  Future<Map<String, dynamic>> checkRelations(Map<String, dynamic> e) async {
    final w = Uri.encodeQueryComponent(e['word'] as String);
    final related = await _words('ml=$w&max=1000');
    final ants = await _words('rel_ant=$w&max=100');
    final syns = await _words('rel_syn=$w&max=100');
    if (related == null || ants == null || syns == null) return e;
    final syn = [
      for (final s in e['syn'] as List<String>)
        if ((related.contains(s) || syns.contains(s)) && !ants.contains(s)) s,
    ];
    // Datamuse has little antonym data, so antonyms are only checked for
    // contradictions (an "antonym" it lists as a synonym).
    final ant = [
      for (final a in e['ant'] as List<String>)
        if (!syns.contains(a)) a,
    ];
    final droppedS = (e['syn'] as List).where((s) => !syn.contains(s));
    final droppedA = (e['ant'] as List).where((a) => !ant.contains(a));
    if (droppedS.isNotEmpty || droppedA.isNotEmpty) {
      stdout.writeln(
        '  ${e['word']}: removed unverified ${[...droppedS, ...droppedA].join(', ')}',
      );
    }
    return {...e, 'syn': syn, 'ant': ant};
  }
}

/// Today's date in India (the jobs run at 06:00 IST), as YYYY-MM-DD.
String todayIst() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 5, minutes: 30))
    .toIso8601String()
    .substring(0, 10);

/// Adds a line to the commit message shared by the day's jobs.
void addCommitLine(String line) =>
    File('.commit-message').writeAsStringSync('$line\n', mode: FileMode.append);

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
