// Fills in meanings in 10 more Indian languages (the `tr` field) for words
// that don't have them yet: today's editorial words first, then the main
// list in study order. Uses whatever free Gemini quota is left after the
// day's new words.
//
//   GEMINI_API_KEY=... dart run translate.dart [maxWords]
//
// Each batch is translated, then corrected by a reviewer pass; a language
// is only stored if it passes the script checks in word_check.dart.
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

const batchSize = 20;

/// Language code -> name, in the order the app lists them.
const languages = {
  'mr': 'Marathi',
  'te': 'Telugu',
  'ta': 'Tamil',
  'gu': 'Gujarati',
  'ur': 'Urdu',
  'kn': 'Kannada',
  'or': 'Odia',
  'ml': 'Malayalam',
  'pa': 'Punjabi',
  'as': 'Assamese',
};

Future<void> main(List<String> args) async {
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set');
    exit(1);
  }
  final maxWords = args.isNotEmpty ? int.parse(args.first) : 80;

  // Every file with cards, and how to check and save it.
  final sources = <_Source>[
    if (File('editorial.json').existsSync())
      _Source(
        'editorial.json',
        (d) => [
          for (final day in (d['days'] as List).take(1))
            ...((day as Map)['words'] as List).cast<Map<String, dynamic>>(),
        ],
        (e) => checkWordEntry(e),
        formatDays,
      ),
    _Source(
      'words.json',
      (d) => (d['words'] as List).cast<Map<String, dynamic>>(),
      (e) => checkWordEntry(e),
      formatWords,
    ),
    for (final pack in ['idioms', 'ows', 'phrasal', 'spelling', 'confusables'])
      if (File('$pack.json').existsSync())
        _Source(
          '$pack.json',
          (d) => (d['items'] as List).cast<Map<String, dynamic>>(),
          (e) => checkPackItem(e, pack),
          formatItems,
        ),
  ];
  for (final s in sources) {
    s.data =
        jsonDecode(File(s.file).readAsStringSync()) as Map<String, dynamic>;
  }

  // 1. Remove translations that break the script rules (e.g. Gujarati
  // letters inside Odia); step 2 translates them again.
  var cleaned = 0;
  for (final s in sources) {
    for (final e in s.entries()) {
      final before = (e['tr'] as Map?)?.length ?? 0;
      final fixed = withoutBadTranslations(e)['tr'];
      if (fixed is Map && fixed.length < before) {
        e['tr'] = fixed;
        cleaned += before - fixed.length;
        s.touched = true;
      }
    }
  }
  if (cleaned > 0) stdout.writeln('Removed $cleaned bad translations.');

  bool missing(Map e) {
    final tr = (e['tr'] as Map?) ?? const {};
    return languages.keys.any((k) => tr[k] == null);
  }

  // 2. Entries still missing a language: today's editorial words first,
  // then words, then topic packs. By reference, so edits land in place.
  final todo = <(Map<String, dynamic>, _Source)>[
    for (final s in sources)
      for (final e in s.entries())
        if (missing(e)) (e, s),
  ].take(maxWords).toList();

  var done = 0;
  if (todo.isNotEmpty) {
    stdout.writeln('Translating ${todo.length} cards.');
    final Gemini ai;
    try {
      ai = Gemini(await pickModels());
    } catch (e) {
      stdout.writeln('Gemini unavailable ($e).');
      _save(sources, cleaned, 0);
      return;
    }
    String label(Map e) => '${e['word'] ?? e['term']}'.toLowerCase();
    for (var i = 0; i < todo.length; i += batchSize) {
      final batch = todo.skip(i).take(batchSize).toList();
      final input = [
        for (final (e, _) in batch)
          {
            'word': label(e),
            'pos': e['pos'] ?? 'phrase',
            'meaning': e['en'],
            'example': e['ex'],
          },
      ];
      try {
        final draft = await ai.json(
          _translatePrompt(jsonEncode(input)),
          schema: _schema,
        );
        final reviewed = await ai.json(
          _reviewPrompt(jsonEncode(input), jsonEncode(draft)),
          schema: _schema,
        );
        final byWord = {
          for (final r in (reviewed as List).cast<Map<String, dynamic>>())
            '${r['word']}'.trim().toLowerCase(): r,
        };
        for (final (e, s) in batch) {
          final r = byWord[label(e)];
          if (r == null) continue;
          final tr = Map<String, dynamic>.from((e['tr'] as Map?) ?? const {});
          var added = 0;
          for (final code in languages.keys) {
            if (tr[code] != null) continue;
            final v = '${r[code] ?? ''}'.trim();
            if (v.isEmpty) continue;
            // Keep a language only if the card still passes every rule.
            if (s.check({
              ...e,
              'tr': {...tr, code: v},
            }).isEmpty) {
              tr[code] = v;
              added++;
            } else {
              stdout.writeln('  ${label(e)}.$code rejected: $v');
            }
          }
          if (added > 0) {
            e['tr'] = tr;
            done++;
            s.touched = true;
          }
        }
      } catch (e) {
        stderr.writeln('Batch failed: $e');
        if ('$e'.contains('All models failed') || '$e'.contains('budget'))
          break;
      }
    }
  } else {
    stdout.writeln('Every card already has all languages.');
  }
  _save(sources, cleaned, done);
}

class _Source {
  _Source(this.file, this.entriesOf, this.check, this.format);
  final String file;
  final List<Map<String, dynamic>> Function(Map<String, dynamic>) entriesOf;
  final List<String> Function(Map<String, dynamic>) check;
  final String Function(Map<String, dynamic>) format;
  late Map<String, dynamic> data;
  bool touched = false;
  List<Map<String, dynamic>> entries() => entriesOf(data);
}

void _save(List<_Source> sources, int cleaned, int done) {
  final today = todayIst();
  for (final s in sources.where((s) => s.touched)) {
    s.data['version'] = (s.data['version'] as int) + 1;
    s.data['updated'] = today;
    File(s.file).writeAsStringSync(s.format(s.data));
  }
  if (cleaned > 0 || done > 0) {
    addCommitLine(
      'Translations: $done cards in more languages'
      '${cleaned > 0 ? ', $cleaned bad ones removed' : ''}',
    );
  }
  stdout.writeln('Translated $done cards; removed $cleaned bad translations.');
}

final _schema = {
  'type': 'ARRAY',
  'items': {
    'type': 'OBJECT',
    'properties': {
      'word': {'type': 'STRING'},
      for (final code in languages.keys) code: {'type': 'STRING'},
    },
    'required': ['word', ...languages.keys],
  },
};

final _langList = [
  for (final e in languages.entries) '${e.key} = ${e.value}',
].join(', ');

String _translatePrompt(String input) =>
    '''
Translate the meaning of each English exam-vocabulary word below into these
Indian languages: $_langList.
For each word and language give 1-3 short, natural equivalents that a
native speaker would actually use for this exact sense (see the meaning and
example), comma-separated, each 1-3 words, in the language's own script
only (Urdu in Urdu/Arabic script, Assamese with Assamese letters such as
ৰ and ৱ, Marathi in Devanagari), the same part of speech as the English
word, with no transliteration, no Latin letters, no explanations and no
"or" phrases. Add nothing beyond the English meaning.
Words:
$input''';

String _reviewPrompt(String input, String draft) =>
    '''
You are a panel of native speakers of $_langList, reviewing translations of
English exam-vocabulary words for students. Nobody else will check them.
For each word, make sure every language gives what a native speaker really
says for this exact sense (see meaning and example), correctly spelt, in
the right script, the same part of speech, 1-3 short comma-separated
equivalents, nothing extra. Marathi must be Marathi (not Hindi), Assamese
must be Assamese (not Bengali), Urdu must be Urdu script. If unsure, use a
simpler word you are sure of. Return the corrected translations for every
word (same words, same order).
Words:
$input
Translations to review:
$draft''';
