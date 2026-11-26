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

import 'common.dart';

const target = 2000;
const batchSize = 5;

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

  // 2. Most frequent first (Datamuse), skipping obscure words.
  final freq = <String, double>{};
  for (final c in candidates) {
    freq[c] = await datamuse.frequency(c) ?? 1;
  }
  candidates
    ..removeWhere((c) => freq[c]! < 0.05)
    ..sort((a, b) => freq[b]!.compareTo(freq[a]!));

  // 3. Write, review, verify, validate, in batches until we have enough.
  final added = <Map<String, dynamic>>[];
  for (
    var i = 0;
    i < candidates.length && added.length < want;
    i += batchSize
  ) {
    final batch = candidates.skip(i).take(batchSize).toList();
    try {
      for (final e in await makeCards(ai, batch)) {
        if (existing.contains(e['id'])) continue;
        existing.add(e['id'] as String);
        added.add(e);
        if (added.length >= want) break;
      }
    } catch (e) {
      stderr.writeln('Batch $batch failed: $e');
      if ('$e'.contains('All models failed') || '$e'.contains('budget')) {
        break;
      }
    }
  }

  if (added.isEmpty) {
    stdout.writeln('No valid words produced; no changes.');
    return;
  }
  final today = todayIst();
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
  addCommitLine('Words v$next: +${added.length} (total $total)');
  stdout.writeln('Added ${added.length}; now v$next with $total words.');
}
