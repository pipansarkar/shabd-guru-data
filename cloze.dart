// Writes one new exam-style cloze passage a day (passages.json) with the
// free Gemini API: an original passage with 5-8 blanks, 4 options each,
// checked by a reviewer pass and the rules in word_check.dart.
//
//   GEMINI_API_KEY=... dart run cloze.dart [count]
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

/// Rotating themes so passages cover what exams use.
const themes = [
  'banking and personal finance',
  'environment and climate',
  'technology in daily life',
  'Indian history and heritage',
  'health and fitness',
  'education and learning',
  'rural development and agriculture',
  'science and discovery',
  'sports and teamwork',
  'economy and employment',
  'society and values',
  'travel and culture',
];

Future<void> main(List<String> args) async {
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set');
    exit(1);
  }
  final file = File('passages.json');
  final data = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'version': 0, 'items': <Object>[]};
  final today = todayIst();
  if (args.isEmpty && data['added'] == today) {
    stdout.writeln('A passage was already added today.');
    return;
  }
  final want = args.isNotEmpty ? int.parse(args.first) : 1;
  final items = (data['items'] as List).cast<Map<String, dynamic>>();
  final titles = {for (final i in items) i['id']};
  final schema = {
    'type': 'OBJECT',
    'properties': {
      'title': {'type': 'STRING'},
      'text': {'type': 'STRING'},
      'blanks': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'options': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
            'answer': {'type': 'INTEGER'},
            'explain': {'type': 'STRING'},
          },
          'required': ['options', 'answer', 'explain'],
        },
      },
    },
    'required': ['title', 'text', 'blanks'],
  };

  final Gemini ai;
  try {
    ai = Gemini(await pickModels());
  } catch (e) {
    stdout.writeln('Gemini unavailable ($e); no changes today.');
    return;
  }
  final added = <Map<String, dynamic>>[];
  for (var n = 0; n < want; n++) {
    final theme = themes[(items.length + n) % themes.length];
    try {
      final draft = await ai.json('''
Write an ORIGINAL cloze test like those in SSC CGL and IBPS PO English
papers, on the theme "$theme".
- title: a short title (3-6 words)
- text: 120-180 words, clear modern English, Indian context welcome, with
  6 blanks written as {1}, {2}, {3}, {4}, {5}, {6} in order (each exactly
  once). Blanks test vocabulary in context: word choice, collocations,
  connectors and the right form of a word.
- blanks: for each blank, 4 single-word or two-word options (all the same
  part of speech and plausible), the index (0-3) of the only correct one,
  and explain: why it is right, in one short sentence.
Nothing political, nothing about real living people. Do not copy any
published passage or exam paper.''', schema: schema);
      final reviewed = await ai.json('''
You are a strict English examiner. Check this cloze test: exactly one
option per blank must be clearly correct and the others clearly wrong in
context; the passage must read naturally once filled in; markers {1}..{n}
must appear in order once each; fix anything wrong (you may change options,
answers or wording). Return the corrected test in the same format.
${jsonEncode(draft)}''', schema: schema);
      final r = reviewed as Map<String, dynamic>;
      final title = '${r['title']}'.trim();
      final item = {
        'id': packId(title),
        'title': title,
        'theme': theme,
        'date': today,
        'text': '${r['text']}'.trim(),
        'blanks': [
          for (final b in (r['blanks'] as List? ?? const []).cast<Map>())
            {
              'options': [
                for (final o in (b['options'] as List? ?? const []))
                  '$o'.trim(),
              ],
              'answer': (b['answer'] as num?)?.toInt() ?? -1,
              'explain': '${b['explain'] ?? ''}'.trim(),
            },
        ],
      };
      final problems = checkClozeItem(item);
      if (problems.isNotEmpty || titles.contains(item['id'])) {
        stdout.writeln('  dropped "$title": ${problems.join('; ')}');
        continue;
      }
      titles.add(item['id']);
      added.add(item);
    } catch (e) {
      stderr.writeln('Passage failed: $e');
      if ('$e'.contains('All models failed') || '$e'.contains('budget')) break;
    }
  }
  if (added.isEmpty) {
    stdout.writeln('No valid passage produced; no changes.');
    return;
  }
  final out = {
    ...data,
    'version': (data['version'] as int) + 1,
    'updated': today,
    'added': today,
    'items': [...items, ...added],
  };
  final problems = checkClozeFile(out, previous: data);
  if (problems.isNotEmpty) {
    stderr.writeln('Not publishing:\n${problems.join('\n')}');
    exit(1);
  }
  file.writeAsStringSync(formatItems(out));
  addCommitLine(
    'Cloze: +${added.length} (${added.map((a) => a['title']).join(', ')})',
  );
  stdout.writeln('Added ${added.length} passage(s).');
}
