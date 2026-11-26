// GENERATED from vocab_builder/lib/data/word_check.dart by
// tool/sync_validator.sh. Edit the app copy, then re-run the script.
//
// Usage: dart run validate.dart words.json [previous_words.json]
import 'dart:convert';
import 'dart:io';

/// Rules every word entry must pass. Pure Dart (no Flutter) so the same file
/// runs in the app, in tests and in the data repo's validator
/// (`shabd-guru-data/validate.dart` is a copy: keep them in sync with
/// `tool/sync_validator.sh`).

const wordPos = {'noun', 'verb', 'adjective', 'adverb'};
const wordExams = {'bank', 'ssc', 'cat', 'cuet', 'upsc'};
final _bengali = RegExp(r'[ঀ-৿]');
final _devanagari = RegExp(r'[ऀ-ॿ]');
final _latin = RegExp(r'[A-Za-z]');

/// Problems with one entry; empty when it is fine.
List<String> checkWordEntry(Object? raw) {
  if (raw is! Map) return ['not an object'];
  final p = <String>[];
  String str(String k) {
    final v = raw[k];
    if (v is! String || v.trim().isEmpty) {
      p.add('$k missing');
      return '';
    }
    return v.trim();
  }

  List<String> list(String k, {bool required = true}) {
    final v = raw[k];
    if (v == null && !required) return const [];
    if (v is! List || v.any((e) => e is! String || e.trim().isEmpty)) {
      p.add('$k must be a list of words');
      return const [];
    }
    if (required && v.isEmpty) p.add('$k empty');
    return [for (final e in v) (e as String).trim().toLowerCase()];
  }

  final id = str('id');
  final word = str('word');
  final pos = str('pos');
  final en = str('en');
  final bn = str('bn');
  final hi = str('hi');
  final ex = str('ex');
  str('trick');
  final syn = list('syn');
  final ant = list('ant');
  final exams = list('exams', required: false);

  if (word.isNotEmpty && id != word.toLowerCase().replaceAll(' ', '-')) {
    p.add('id must be the lower-case word');
  }
  if (pos.isNotEmpty && !wordPos.contains(pos)) p.add('pos "$pos" unknown');
  if (en.isNotEmpty && !_latin.hasMatch(en)) p.add('en not English');
  if (bn.isNotEmpty && !_bengali.hasMatch(bn)) p.add('bn not Bengali script');
  if (hi.isNotEmpty && !_devanagari.hasMatch(hi)) p.add('hi not Devanagari');
  if (bn.isNotEmpty && _devanagari.hasMatch(bn)) p.add('bn contains Hindi');
  if (hi.isNotEmpty && _bengali.hasMatch(hi)) p.add('hi contains Bengali');
  if (syn.toSet().intersection(ant.toSet()).isNotEmpty) {
    p.add('a word is both synonym and antonym');
  }
  final w = word.toLowerCase();
  if (w.isNotEmpty && (syn.contains(w) || ant.contains(w))) {
    p.add('headword listed as its own synonym/antonym');
  }
  if (w.isNotEmpty && ex.isNotEmpty) {
    // The example must use the word (allowing endings like -ed, -s).
    final stem = w.substring(0, (w.length - 2).clamp(4, w.length));
    if (!ex.toLowerCase().contains(stem)) p.add('example does not use word');
  }
  for (final e in exams) {
    if (!wordExams.contains(e)) p.add('exam "$e" unknown');
  }
  return p;
}

/// Problems with a whole words file, as "id: problem" lines. With [previous]
/// (the currently published file) it also enforces publishing rules: the
/// version goes up and existing words keep their place, so users' progress
/// and study order never shift.
List<String> checkWordsFile(Object? raw, {Object? previous}) {
  if (raw is! Map) return ['file is not a JSON object'];
  final out = <String>[];
  final version = raw['version'];
  if (version is! int) out.add('version must be an integer');
  final words = raw['words'];
  if (words is! List) return [...out, 'words must be a list'];
  final seen = <String>{};
  for (var i = 0; i < words.length; i++) {
    final e = words[i];
    final id = e is Map && e['id'] is String ? e['id'] as String : '#$i';
    for (final problem in checkWordEntry(e)) {
      out.add('$id: $problem');
    }
    if (!seen.add(id)) out.add('$id: duplicate id');
  }
  if (previous is Map && previous['words'] is List) {
    final pv = previous['version'];
    if (version is int && pv is int && version <= pv) {
      out.add('version must be higher than $pv');
    }
    final oldIds = [
      for (final e in previous['words'] as List)
        if (e is Map) e['id'],
    ];
    for (var i = 0; i < oldIds.length; i++) {
      if (i >= words.length ||
          words[i] is! Map ||
          (words[i] as Map)['id'] != oldIds[i]) {
        out.add(
          'existing words must stay in order; new words go at the end '
          '(first difference at position $i, "${oldIds[i]}")',
        );
        break;
      }
    }
  }
  return out;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run validate.dart words.json [previous.json]');
    exit(2);
  }
  final next = jsonDecode(File(args[0]).readAsStringSync());
  final prev = args.length > 1
      ? jsonDecode(File(args[1]).readAsStringSync())
      : null;
  final problems = checkWordsFile(next, previous: prev);
  if (problems.isEmpty) {
    final n = (next['words'] as List).length;
    stdout.writeln('OK: version ${next['version']}, $n words');
    return;
  }
  problems.forEach(stderr.writeln);
  stderr.writeln('${problems.length} problem(s)');
  exit(1);
}
