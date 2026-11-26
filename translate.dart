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

  final wordsFile = File('words.json');
  final words =
      jsonDecode(wordsFile.readAsStringSync()) as Map<String, dynamic>;
  final edFile = File('editorial.json');
  final editorial = edFile.existsSync()
      ? jsonDecode(edFile.readAsStringSync()) as Map<String, dynamic>
      : null;

  bool missing(Map e) {
    final tr = (e['tr'] as Map?) ?? const {};
    return languages.keys.any((k) => tr[k] == null);
  }

  // Entries to translate, by reference so edits land in the loaded files.
  final todo = <Map<String, dynamic>>[
    if (editorial != null)
      for (final d in (editorial['days'] as List).take(1))
        for (final w in (d as Map)['words'] as List)
          if (missing(w as Map)) w as Map<String, dynamic>,
    for (final w in words['words'] as List)
      if (missing(w as Map)) w as Map<String, dynamic>,
  ].take(maxWords).toList();
  if (todo.isEmpty) {
    stdout.writeln('Every word already has all languages.');
    return;
  }
  stdout.writeln('Translating ${todo.length} words.');

  final ai = Gemini(await pickModels());
  var done = 0;
  var touchedWords = false, touchedEditorial = false;
  final edIds = {
    if (editorial != null)
      for (final d in (editorial['days'] as List).take(1))
        for (final w in (d as Map)['words'] as List) (w as Map)['id'],
  };
  for (var i = 0; i < todo.length; i += batchSize) {
    final batch = todo.skip(i).take(batchSize).toList();
    final input = [
      for (final e in batch)
        {
          'word': e['word'],
          'pos': e['pos'],
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
      for (final e in batch) {
        final r = byWord[e['word']];
        if (r == null) continue;
        final tr = Map<String, dynamic>.from((e['tr'] as Map?) ?? const {});
        var added = 0;
        for (final code in languages.keys) {
          if (tr[code] != null) continue;
          final v = '${r[code] ?? ''}'.trim();
          if (v.isEmpty) continue;
          // Keep a language only if the entry still passes every rule.
          final trial = {
            ...e,
            'tr': {...tr, code: v},
          };
          if (checkWordEntry(trial).isEmpty) {
            tr[code] = v;
            added++;
          } else {
            stdout.writeln('  ${e['word']}.$code rejected: $v');
          }
        }
        if (added > 0) {
          e['tr'] = tr;
          done++;
          if (edIds.contains(e['id'])) {
            touchedEditorial = true;
          } else {
            touchedWords = true;
          }
        }
      }
    } catch (e) {
      stderr.writeln('Batch failed: $e');
      if ('$e'.contains('All models failed') || '$e'.contains('budget')) break;
    }
  }

  final today = todayIst();
  if (touchedWords) {
    words['version'] = (words['version'] as int) + 1;
    words['updated'] = today;
    wordsFile.writeAsStringSync(formatWords(words));
  }
  if (touchedEditorial && editorial != null) {
    editorial['version'] = (editorial['version'] as int) + 1;
    editorial['updated'] = today;
    edFile.writeAsStringSync(formatDays(editorial));
  }
  if (done > 0) addCommitLine('Translations: $done words in more languages');
  stdout.writeln('Translated $done words.');
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
