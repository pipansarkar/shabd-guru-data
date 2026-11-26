// Adds new words to words.json using the free Gemini API (Google AI Studio).
// Run by .github/workflows/daily-words.yml; needs GEMINI_API_KEY.
//
//   GEMINI_API_KEY=... dart run generate.dart [count]
//
// Steps: suggest candidate words -> write entries in small batches -> a
// second "reviewer" pass corrects them -> every entry must pass the same
// rules the app enforces (word_check.dart) or it is dropped. Existing words
// are never touched; new words are appended and the version is bumped.
// Exits 0 without changes when nothing valid was produced.
import 'dart:convert';
import 'dart:io';

import 'word_check.dart';

const target = 2000;
const batchSize = 5;
final key = Platform.environment['GEMINI_API_KEY'] ?? '';
final preferredModel = Platform.environment['GEMINI_MODEL'] ?? '';

Future<void> main(List<String> args) async {
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set');
    exit(1);
  }
  final file = File('words.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final words = data['words'] as List;
  final want = (args.isNotEmpty ? int.parse(args.first) : 25).clamp(
    0,
    target - words.length,
  );
  if (want <= 0) {
    stdout.writeln('List already has ${words.length} words; nothing to do.');
    return;
  }
  final existing = {for (final w in words) (w as Map)['id'] as String};
  final models = await pickModels();
  stdout.writeln('Models: ${models.join(', ')}');
  final ai = Gemini(models);

  // 1. Candidate headwords, rotating through the alphabet so each run looks
  // at different words and the exclusion list stays short.
  final version = data['version'] as int;
  const letters = 'abcdefghijklmnoprstuvw';
  final pick = [
    letters[(version * 2) % letters.length],
    letters[(version * 2 + 1) % letters.length],
  ];
  final have = existing.where((id) => pick.any(id.startsWith)).toList()..sort();
  final suggested = await ai.json(
    '''
You are building a vocabulary list for Indian competitive exams (IBPS/SBI
Bank PO and Clerk, RBI, SSC CGL/CHSL, CAT, CUET).
List 60 single English words starting with the letter "${pick[0]}" or
"${pick[1]}" that appear most often in these exams' synonym/antonym, cloze,
error-spotting and reading-comprehension questions, and in newspaper
editorials. Prefer genuinely high-frequency exam words; no proper nouns, no
phrases, no obscure or archaic words.
Do NOT include any of these (already in the list): ${have.join(', ')}.
Return a JSON array of lower-case words, most useful first.''',
    schema: {
      'type': 'ARRAY',
      'items': {'type': 'STRING'},
    },
  );
  final candidates = <String>[];
  for (final s in (suggested as List).cast<String>()) {
    final w = s.trim().toLowerCase();
    if (!RegExp(r'^[a-z]{3,}$').hasMatch(w)) continue;
    if (existing.contains(w) || candidates.contains(w)) continue;
    if (nearDuplicate(w, existing)) continue;
    candidates.add(w);
  }
  stdout.writeln('Candidates (${candidates.length}): ${candidates.join(', ')}');

  // 2 + 3. Write, review, validate, in batches until we have enough.
  final added = <Map<String, dynamic>>[];
  for (
    var i = 0;
    i < candidates.length && added.length < want;
    i += batchSize
  ) {
    final batch = candidates.skip(i).take(batchSize).toList();
    try {
      final draft = await ai.json(writePrompt(batch), schema: entriesSchema);
      final reviewed = await ai.json(
        reviewPrompt(jsonEncode(draft)),
        schema: entriesSchema,
      );
      for (final raw in reviewed as List) {
        final e = normalise(raw as Map<String, dynamic>);
        final id = e['id'] as String;
        final problems = checkWordEntry(e);
        if (!batch.contains(id) || existing.contains(id)) continue;
        if (problems.isNotEmpty) {
          stdout.writeln('  dropped $id: ${problems.join('; ')}');
          continue;
        }
        existing.add(id);
        added.add(e);
        if (added.length >= want) break;
      }
    } catch (e) {
      stderr.writeln('Batch $batch failed: $e');
    }
  }

  if (added.isEmpty) {
    stdout.writeln('No valid words produced; no changes.');
    return;
  }
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final next = version + 1;
  final out = {
    ...data,
    'version': next,
    'updated': today,
    'words': [...words, ...added],
  };
  file.writeAsStringSync(formatWords(out));
  final total = words.length + added.length;
  final log = File('CHANGELOG.md');
  final lines = log.readAsLinesSync();
  final line =
      '- v$next ($today): +${added.length} words: '
      '${added.map((e) => e['word']).join(', ')} (total $total)';
  log.writeAsStringSync(
    [lines.first, '', line, ...lines.skip(2)].join('\n') + '\n',
  );
  File(
    '.commit-message',
  ).writeAsStringSync('Words v$next: +${added.length} (total $total)');
  stdout.writeln('Added ${added.length}; now v$next with $total words.');
}

/// Skips "abatement" when "abate" exists, and vice versa.
bool nearDuplicate(String w, Set<String> existing) => existing.any(
  (e) =>
      (e.length >= 5 && w.startsWith(e)) || (w.length >= 5 && e.startsWith(w)),
);

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

String writePrompt(List<String> batch) =>
    '''
Write vocabulary cards for Indian exam aspirants (Bank, SSC, CAT, CUET) for
exactly these words: ${batch.join(', ')}.
For each word, in the sense most often tested in exams:
- word: the word, lower case
- pos: noun, verb, adjective or adverb
- en: a short plain-English meaning, under 12 words, in your own words
- bn: 1-3 natural Bengali equivalents, comma-separated, Bengali script only
- hi: 1-3 natural Hindi equivalents, comma-separated, Devanagari only
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
      !RegExp(r'image|tts|audio|live|embedding|thinking-exp').hasMatch(n);
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
    ...flash.where((m) => m != preferredModel).take(4),
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
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(minutes: 3));
    final text = await res.transform(utf8.decoder).join();
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

  /// Asks for JSON matching [schema]; tries each model in turn, waiting and
  /// retrying on rate limits.
  Future<Object?> json(
    String prompt, {
    required Map<String, Object> schema,
  }) async {
    Object? lastError;
    for (final model in models) {
      for (var attempt = 0; attempt < 3; attempt++) {
        // Stay well under free-tier requests-per-minute.
        await Future<void>.delayed(const Duration(seconds: 7));
        try {
          final res = await request('POST', 'models/$model:generateContent', {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.4,
              'responseMimeType': 'application/json',
              'responseSchema': schema,
            },
          });
          final parts =
              ((res['candidates'] as List).first as Map)['content']['parts']
                  as List;
          final text = parts.map((p) => (p as Map)['text'] ?? '').join();
          return jsonDecode(text);
        } catch (e) {
          lastError = e;
          final msg = '$e';
          stderr.writeln('  $model attempt ${attempt + 1}: $msg');
          if (msg.startsWith('HttpException: 429') ||
              msg.contains('503') ||
              msg.contains('500')) {
            await Future<void>.delayed(Duration(seconds: 30 * (attempt + 1)));
            continue;
          }
          break; // other errors: try the next model
        }
      }
    }
    throw StateError('All models failed: $lastError');
  }
}
