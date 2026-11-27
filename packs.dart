// Grows the topic packs: idioms, one word substitution (ows), phrasal
// verbs, spelling, confusable words and the Word Roots course. Each run
// works on one pack (rotating daily), writing every item in English,
// Bengali, Hindi and the 10 other languages, then a reviewer pass, then the
// rules in word_check.dart.
//
//   GEMINI_API_KEY=... dart run packs.dart [pack] [count]
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

/// Language code -> name for the `tr` map.
const otherLanguages = {
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

class PackSpec {
  const PackSpec(this.name, this.perRun, this.batch, this.what, this.fields);
  final String name;
  final int perRun, batch;

  /// What to suggest, for the candidate prompt.
  final String what;

  /// Field rules for the writing prompt.
  final String fields;
}

const specs = {
  'idioms': PackSpec(
    'idioms',
    20,
    10,
    'English idioms and phrases most often asked in SSC, Bank and state PSC exams (e.g. "a bolt from the blue")',
    '- term: the idiom, lower case\n'
        '- en: its real meaning (not word-by-word), under 12 words\n'
        '- ex: one original sentence using the idiom',
  ),
  'ows': PackSpec(
    'ows',
    20,
    10,
    'one word substitutions most often asked in SSC and Bank exams (a single word that replaces a description, e.g. "misanthrope" for "one who hates mankind")',
    '- term: the single word, lower case\n'
        '- clue: the description it replaces, exam style ("One who ...", "A place where ..."), not containing the word\n'
        '- en: a short plain meaning of the word\n'
        '- ex: one original sentence using the word',
  ),
  'phrasal': PackSpec(
    'phrasal',
    20,
    10,
    'English phrasal verbs most useful for Indian competitive exams (e.g. "look down on", "put off")',
    '- term: the phrasal verb, lower case\n'
        '- en: its meaning, under 10 words\n'
        '- ex: one original sentence using it',
  ),
  'spelling': PackSpec(
    'spelling',
    20,
    10,
    'English words most often misspelt, as tested in SSC spelling questions (e.g. "accommodation", "embarrass")',
    '- term: the correct spelling, lower case\n'
        '- wrong: 2-3 common misspellings (lower case, never the correct one)\n'
        '- en: a short meaning\n'
        '- tip: a short rule or trick to remember the spelling\n'
        '- ex: one original sentence using the word',
  ),
  'confusables': PackSpec(
    'confusables',
    12,
    6,
    'groups of 2-3 English words that exam takers often confuse (e.g. affect/effect, complement/compliment, principal/principle)',
    '- words: the 2-3 confused words, lower case\n'
        '- term: the words joined with " vs " (e.g. "affect vs effect")\n'
        '- en: how to tell them apart, one or two short sentences\n'
        '- tip: a short memory trick\n'
        '- ex: one original sentence that correctly uses every word in the group',
  ),
  'roots': PackSpec(
    'roots',
    4,
    2,
    'Greek and Latin word roots (and a few Old English/French ones) that unlock the most exam vocabulary (e.g. "bene" = good, "chron" = time)',
    '- term: the root, lower case (e.g. "bene")\n'
        '- forms: other spellings of the root seen in words (e.g. ["beni", "bon"])\n'
        '- origin: Latin, Greek, Old English or French\n'
        '- unit: one of: ${''}UNITS\n'
        '- en: what the root means, a few words\n'
        '- note: a short original lesson (2-3 sentences) explaining the root and how it builds words\n'
        '- words: 5-7 common exam words containing the root, each with word, en (meaning under 10 words), bn, hi and tr\n'
        '- ex: one original sentence using one of those words',
  ),
};

final _trSchema = {
  'type': 'OBJECT',
  'properties': {
    for (final c in otherLanguages.keys) c: {'type': 'STRING'},
  },
  'required': otherLanguages.keys.toList(),
};

Map<String, Object> _itemSchema(String pack) {
  final props = <String, Object>{
    'term': {'type': 'STRING'},
    'en': {'type': 'STRING'},
    'bn': {'type': 'STRING'},
    'hi': {'type': 'STRING'},
    'tr': _trSchema,
    'ex': {'type': 'STRING'},
    'exams': {
      'type': 'ARRAY',
      'items': {
        'type': 'STRING',
        'enum': ['bank', 'ssc', 'cat', 'cuet', 'upsc'],
      },
    },
  };
  final req = ['term', 'en', 'bn', 'hi', 'tr', 'ex'];
  List<String> list = const [];
  switch (pack) {
    case 'ows':
      props['clue'] = {'type': 'STRING'};
      list = ['clue'];
    case 'spelling':
      props['wrong'] = {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      };
      props['tip'] = {'type': 'STRING'};
      list = ['wrong', 'tip'];
    case 'confusables':
      props['words'] = {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      };
      props['tip'] = {'type': 'STRING'};
      list = ['words', 'tip'];
    case 'roots':
      props['forms'] = {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      };
      props['origin'] = {
        'type': 'STRING',
        'enum': ['Latin', 'Greek', 'Old English', 'French'],
      };
      props['unit'] = {'type': 'STRING', 'enum': rootUnits};
      props['note'] = {'type': 'STRING'};
      props['words'] = {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'word': {'type': 'STRING'},
            'en': {'type': 'STRING'},
            'bn': {'type': 'STRING'},
            'hi': {'type': 'STRING'},
            'tr': _trSchema,
          },
          'required': ['word', 'en', 'bn', 'hi', 'tr'],
        },
      };
      list = ['forms', 'origin', 'unit', 'note', 'words'];
  }
  return {
    'type': 'ARRAY',
    'items': {
      'type': 'OBJECT',
      'properties': props,
      'required': [...req, ...list],
    },
  };
}

final _langRules =
    '''
- bn: Bengali, hi: Hindi, and tr: the same meaning in
  ${otherLanguages.entries.map((e) => '${e.key}=${e.value}').join(', ')}.
  Each: 1-3 short natural equivalents a native speaker really uses for this
  exact sense (for idioms and explanations a short natural phrase), in the
  language's own script only (Urdu in Urdu script, Assamese with Assamese
  letters such as ৰ ৱ, Marathi in Devanagari), no Latin letters, no
  transliteration, nothing beyond the English meaning. Marathi must be
  Marathi (not Hindi); Assamese must be Assamese (not Bengali).''';

Future<void> main(List<String> args) async {
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set');
    exit(1);
  }
  // Rotate one pack per day, skipping full ones.
  final day = DateTime.now().toUtc().difference(DateTime.utc(2026)).inDays;
  final order = packTargets.keys.toList();
  String? pack = args.isNotEmpty ? args[0] : null;
  final files = <String, Map<String, dynamic>>{};
  Map<String, dynamic> load(String p) =>
      files[p] ??= File('$p.json').existsSync()
      ? jsonDecode(File('$p.json').readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'version': 0, 'items': <Object>[]};
  if (pack == null) {
    for (var i = 0; i < order.length; i++) {
      final p = order[(day + i) % order.length];
      if ((load(p)['items'] as List).length < packTargets[p]!) {
        pack = p;
        break;
      }
    }
  }
  if (pack == null) {
    stdout.writeln('Every pack is full.');
    return;
  }
  // A second (backup) run on the same day adds nothing.
  if (args.isEmpty &&
      packTargets.keys.any((k) => load(k)['grown'] == todayIst())) {
    stdout.writeln('A topic pack was already grown today.');
    return;
  }
  final spec = specs[pack]!;
  final data = load(pack);
  final items = (data['items'] as List).cast<Map<String, dynamic>>();
  final want = (args.length > 1 ? int.parse(args[1]) : spec.perRun).clamp(
    0,
    packTargets[pack]! - items.length,
  );
  final existing = {for (final i in items) i['id'] as String};
  stdout.writeln('Pack $pack: ${items.length} items, adding up to $want.');

  final ai = Gemini(await pickModels());
  // 1. Candidates. Long packs rotate by first letter to keep prompts short.
  var avoid = items.map((i) => i['term'] as String).toList();
  var letterNote = '';
  if (avoid.length > 150) {
    const letters = 'abcdefghilmnoprstu';
    final l = letters[(data['version'] as int) % letters.length];
    letterNote = ' Each must start with the letter "$l".';
    avoid = avoid.where((t) => t.startsWith(l)).toList();
  }
  final Object? suggested;
  try {
    suggested = await ai.json(
      '''
List ${want * 2} ${spec.what}.$letterNote
Most useful and most frequently tested first. No duplicates.
Do NOT include any of these (already in the list): ${avoid.join('; ')}.
Return a JSON array of strings (for groups, join the words with " vs ").''',
      schema: {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    );
  } catch (e) {
    stdout.writeln('Gemini unavailable ($e); no changes today.');
    return;
  }
  final candidates = <String>[];
  for (final s in (suggested as List).cast<String>()) {
    final t = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final id = packId(t);
    if (id.isEmpty ||
        existing.contains(id) ||
        candidates.any((c) => packId(c) == id)) {
      continue;
    }
    candidates.add(t);
  }
  stdout.writeln('Candidates: ${candidates.join('; ')}');

  // 2. Write + review + validate in batches.
  final added = <Map<String, dynamic>>[];
  final schema = _itemSchema(pack);
  final fields = spec.fields.replaceAll('${''}UNITS', rootUnits.join('; '));
  for (
    var i = 0;
    i < candidates.length && added.length < want;
    i += spec.batch
  ) {
    final batch = candidates.skip(i).take(spec.batch).toList();
    try {
      final draft = await ai.json('''
Write study cards for Indian exam aspirants (SSC, Bank, CAT, CUET, state PSC)
for exactly these: ${batch.join('; ')}.
Fields:
$fields
$_langRules
- exams: which of bank, ssc, cat, cuet, upsc it suits
All text must be original: never copy from dictionaries, exam-prep books
(such as Word Power Made Easy, Blackbook, SP Bakshi) or coaching material.
Examples: max 20 words, Indian everyday context welcome, nothing political,
offensive or about real living people.''', schema: schema);
      final reviewed = await ai.json('''
You are a strict panel: an English teacher for Indian competitive exams and
native speakers of Bengali, Hindi, ${otherLanguages.values.join(', ')}.
Nobody else checks these cards before students see them. Fix anything
wrong: meanings must be accurate (idioms: the real meaning), examples must
use the item correctly, every translation must be natural, correctly spelt,
in the right script and exactly the English sense (Marathi not Hindi,
Assamese not Bengali, Urdu in Urdu script). For spelling cards the
misspellings must really be wrong. For roots, every word must really come
from that root. Return all cards corrected, same items, same order.
Cards:
${jsonEncode(draft)}''', schema: schema);
      for (final raw in (reviewed as List).cast<Map<String, dynamic>>()) {
        final e = _normalise(raw, pack);
        final id = e['id'] as String;
        if (existing.contains(id) || !batch.any((b) => packId(b) == id))
          continue;
        _dropBadTranslations(e, pack);
        final problems = checkPackItem(e, pack);
        if (problems.isNotEmpty) {
          stdout.writeln('  dropped $id: ${problems.join('; ')}');
          continue;
        }
        existing.add(id);
        added.add(e);
        if (added.length >= want) break;
      }
    } catch (e) {
      stderr.writeln('Batch failed: $e');
      if ('$e'.contains('All models failed') || '$e'.contains('budget')) break;
    }
  }
  if (added.isEmpty) {
    stdout.writeln('No valid items produced; no changes.');
    return;
  }
  final out = {
    'version': (data['version'] as int) + 1,
    'updated': todayIst(),
    'grown': todayIst(),
    'items': [...items, ...added],
  };
  final problems = checkPackFile(out, pack, previous: data);
  if (problems.isNotEmpty) {
    stderr.writeln('Not publishing $pack:\n${problems.join('\n')}');
    exit(1);
  }
  File('$pack.json').writeAsStringSync(formatItems(out));
  addCommitLine(
    '${pack[0].toUpperCase()}${pack.substring(1)} v${out['version']}: '
    '+${added.length} (total ${(out['items'] as List).length})',
  );
  stdout.writeln('Added ${added.length} to $pack.');
}

Map<String, dynamic> _normalise(Map<String, dynamic> r, String pack) {
  String s(Object? v) => '${v ?? ''}'.trim();
  List<String> l(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (s(x).isNotEmpty) s(x).toLowerCase(),
  ];
  Map<String, String> tr(Object? v) => {
    for (final e in ((v as Map?) ?? const {}).entries)
      if (otherLanguages.containsKey(e.key) && s(e.value).isNotEmpty)
        '${e.key}': s(e.value),
  };
  var term = s(r['term']).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final e = <String, dynamic>{};
  if (pack == 'confusables') {
    final ws = l(r['words']);
    term = ws.join(' vs ');
    e['words'] = ws;
  }
  e.addAll({
    'id': packId(term),
    'term': term,
    'en': s(r['en']),
    'bn': s(r['bn']),
    'hi': s(r['hi']),
    'tr': tr(r['tr']),
    'ex': s(r['ex']),
    'exams': l(r['exams']),
  });
  switch (pack) {
    case 'ows':
      e['clue'] = s(r['clue']);
    case 'spelling':
      e['wrong'] = l(r['wrong']).where((w) => w != term).toList();
      e['tip'] = s(r['tip']);
    case 'confusables':
      e['tip'] = s(r['tip']);
    case 'roots':
      e['forms'] = l(r['forms']);
      e['origin'] = s(r['origin']);
      e['unit'] = s(r['unit']);
      e['note'] = s(r['note']);
      e['words'] = [
        for (final w in (r['words'] as List? ?? const []))
          if (w is Map)
            {
              'word': s(w['word']).toLowerCase(),
              'en': s(w['en']),
              'bn': s(w['bn']),
              'hi': s(w['hi']),
              'tr': tr(w['tr']),
            },
      ];
  }
  return e;
}

/// Removes single translations that fail the script rules, so one bad
/// language doesn't throw away the whole card.
void _dropBadTranslations(Map<String, dynamic> e, String pack) {
  void clean(Map<String, dynamic> m) {
    final tr = Map<String, String>.from(m['tr'] as Map? ?? const {});
    tr.removeWhere((code, v) {
      final p = <String>[];
      checkTranslations({code: v}, p);
      return p.isNotEmpty;
    });
    m['tr'] = tr;
  }

  clean(e);
  if (pack == 'roots') {
    for (final w in (e['words'] as List).cast<Map<String, dynamic>>()) {
      clean(w);
    }
    // Drop derived words that don't contain the root rather than the lesson.
    final forms = {
      e['term'] as String,
      ...(e['forms'] as List).cast<String>(),
    }.map((f) => f.replaceAll('-', ''));
    (e['words'] as List).removeWhere(
      (w) => !forms.any(((w as Map)['word'] as String).contains),
    );
  }
}
