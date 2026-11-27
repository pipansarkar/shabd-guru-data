// GENERATED from vocab_builder/lib/data/word_check.dart by
// tool/sync_validator.sh. Edit the app copy, then re-run the script.
/// Rules every word entry must pass. Pure Dart (no Flutter) so the same file
/// runs in the app, in tests and in the data repo's validator
/// (`shabd-guru-data/validate.dart` is a copy: keep them in sync with
/// `tool/sync_validator.sh`).
library;

const wordPos = {'noun', 'verb', 'adjective', 'adverb'};
const wordExams = {'bank', 'ssc', 'cat', 'cuet', 'upsc'};
final _bengali = RegExp(r'[ঀ-৿]');
final _devanagari = RegExp(r'[ऀ-ॿ]');
final _latin = RegExp(r'[A-Za-z]');

/// Characters allowed in any script: spaces, digits, punctuation, dandas,
/// zero-width joiners.
final _neutral = RegExp(
  "[\\s0-9.,;:!?()\\[\\]'\"/\\-\u2013\u2014\u2018\u2019\u201c\u201d\u2026\u0964\u0965\u200c\u200d]",
);

/// True when [v] has at least one letter of [script] and every other
/// character is either in [script] or neutral (no mixed scripts such as
/// Malayalam letters inside Assamese).
bool onlyScript(String v, RegExp script) {
  var any = false;
  for (final ch in v.runes.map(String.fromCharCode)) {
    if (_neutral.hasMatch(ch)) continue;
    if (!script.hasMatch(ch)) return false;
    any = true;
  }
  return any;
}

/// [raw] with any extra-language translation that breaks the script rules
/// removed, so one bad language never hides the whole card. Also cleans
/// derived words in Word Roots lessons.
Map<String, dynamic> withoutBadTranslations(Map raw) {
  Map<String, dynamic> clean(Map m) {
    final out = Map<String, dynamic>.from(m);
    final tr = m['tr'];
    if (tr is Map) {
      out['tr'] = {
        for (final e in tr.entries)
          if (translationScripts[e.key] case final script?)
            if (e.value is String && onlyScript(e.value as String, script))
              '${e.key}': e.value,
      };
    }
    return out;
  }

  final out = clean(raw);
  final words = raw['words'];
  if (words is List && words.isNotEmpty && words.first is Map) {
    out['words'] = [for (final w in words) w is Map ? clean(w) : w];
  }
  return out;
}

/// Extra meaning languages, stored in an entry's optional `tr` map
/// (language code -> meaning), each with the Unicode script it must use.
/// Bengali (`bn`) and Hindi (`hi`) are required top-level fields instead.
final translationScripts = <String, RegExp>{
  'mr': RegExp(r'[\u0900-\u097F]'), // Marathi: Devanagari
  'gu': RegExp(r'[\u0A80-\u0AFF]'), // Gujarati
  'pa': RegExp(r'[\u0A00-\u0A7F]'), // Punjabi: Gurmukhi
  'or': RegExp(r'[\u0B00-\u0B7F]'), // Odia
  'as': RegExp(r'[\u0980-\u09FF]'), // Assamese: Bengali-Assamese script
  'ta': RegExp(r'[\u0B80-\u0BFF]'), // Tamil
  'te': RegExp(r'[\u0C00-\u0C7F]'), // Telugu
  'kn': RegExp(r'[\u0C80-\u0CFF]'), // Kannada
  'ml': RegExp(r'[\u0D00-\u0D7F]'), // Malayalam
  'ur': RegExp(r'[\u0600-\u06FF]'), // Urdu: Arabic script
};

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
  checkTranslations(raw['tr'], p);
  final lvl = raw['lvl'];
  if (lvl != null && (lvl is! int || lvl < 1 || lvl > 3)) {
    p.add('lvl must be 1, 2 or 3');
  }

  if (word.isNotEmpty && id != word.toLowerCase().replaceAll(' ', '-')) {
    p.add('id must be the lower-case word');
  }
  if (pos.isNotEmpty && !wordPos.contains(pos)) p.add('pos "$pos" unknown');
  if (en.isNotEmpty && !_latin.hasMatch(en)) p.add('en not English');
  if (bn.isNotEmpty && !onlyScript(bn, _bengali)) {
    p.add('bn not Bengali script');
  }
  if (hi.isNotEmpty && !onlyScript(hi, _devanagari)) p.add('hi not Devanagari');
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

/// Level from how common a word is in real English (occurrences per
/// million words): 1 basic, 2 intermediate, 3 advanced.
int levelForFrequency(double perMillion) =>
    perMillion >= 3 ? 1 : (perMillion >= 1 ? 2 : 3);

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Problems with editorial.json: days newest first, each with up to 10
/// valid word entries that link to the newspaper article they came from.
List<String> checkEditorialFile(Object? raw, {Object? previous}) {
  if (raw is! Map) return ['file is not a JSON object'];
  final out = <String>[];
  if (raw['version'] is! int) out.add('version must be an integer');
  final days = raw['days'];
  if (days is! List) return [...out, 'days must be a list'];
  String? last;
  for (final d in days) {
    if (d is! Map || d['date'] is! String || !_date.hasMatch(d['date'])) {
      out.add('day without a valid date');
      continue;
    }
    final date = d['date'] as String;
    if (last != null && date.compareTo(last) >= 0) {
      out.add('$date: days must be newest first, no repeats');
    }
    last = date;
    final words = d['words'];
    if (words is! List || words.isEmpty || words.length > 10) {
      out.add('$date: needs 1-10 words');
      continue;
    }
    final ids = <String>{};
    for (final w in words) {
      final id = w is Map && w['id'] is String ? w['id'] as String : '?';
      for (final p in checkWordEntry(w)) {
        out.add('$date $id: $p');
      }
      if (!ids.add(id)) out.add('$date $id: duplicate');
      final src = w is Map ? w['source'] : null;
      if (src is! Map ||
          src['paper'] is! String ||
          (src['headline'] as Object?) is! String ||
          (src['headline'] as String).trim().isEmpty ||
          src['url'] is! String ||
          !(src['url'] as String).startsWith('https://')) {
        out.add('$date $id: source needs paper, headline and https url');
      }
    }
  }
  if (previous is Map) {
    final pv = previous['version'];
    final v = raw['version'];
    if (v is int && pv is int && v <= pv) {
      out.add('version must be higher than $pv');
    }
  }
  return out;
}

/// Problems with exams.json (upcoming exam dates for the countdown).
List<String> checkExamsFile(Object? raw) {
  if (raw is! Map) return ['file is not a JSON object'];
  final out = <String>[];
  if (raw['version'] is! int) out.add('version must be an integer');
  final exams = raw['exams'];
  if (exams is! List) return [...out, 'exams must be a list'];
  for (final e in exams) {
    if (e is! Map ||
        e['name'] is! String ||
        (e['name'] as String).trim().isEmpty ||
        e['exam'] is! String ||
        e['date'] is! String ||
        !_date.hasMatch(e['date'] as String) ||
        DateTime.tryParse(e['date'] as String) == null) {
      out.add('bad exam entry: $e');
    }
  }
  return out;
}

/// Adds problems with an optional `tr` map (extra languages) to [p].
void checkTranslations(Object? tr, List<String> p) {
  if (tr == null) return;
  if (tr is! Map) {
    p.add('tr must be an object');
    return;
  }
  for (final e in tr.entries) {
    final script = translationScripts[e.key];
    final v = e.value;
    if (script == null) {
      p.add('tr: unknown language "${e.key}"');
    } else if (v is! String || v.trim().isEmpty) {
      p.add('tr.${e.key} empty');
    } else if (!onlyScript(v, script)) {
      p.add('tr.${e.key} not in its script');
    }
  }
}

/// Topic packs, each published as its own file (`<kind>.json`), with the
/// number of items each pack grows to.
const packTargets = {
  'idioms': 600,
  'ows': 800,
  'phrasal': 300,
  'spelling': 300,
  'confusables': 200,
  'roots': 150,
};

/// Themed units of the Word Roots course, in teaching order.
const rootUnits = [
  'People and personality',
  'Speaking and writing',
  'Mind and feelings',
  'Actions and movement',
  'Time and place',
  'Size, number and amount',
  'Good, bad and judgement',
  'Society, law and power',
  'Life, body and nature',
  'Seeing, hearing and knowing',
];

/// "Beat about the bush" -> "beat-about-the-bush".
String packId(String term) => term
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .trim()
    .replaceAll(RegExp(r' +'), '-');

String _stem(String w) => w.substring(0, (w.length - 2).clamp(3, w.length));

/// Problems with one pack item; empty when fine.
///
/// Every item: id, term, en (meaning / explanation), bn, hi, ex (original
/// example using the term), optional tr, tip, exams. Extra per pack:
/// ows has `clue` ("One who ..."), spelling has `wrong` (common
/// misspellings), confusables has `words` (the 2-3 easily confused words).
List<String> checkPackItem(Object? raw, String pack) {
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

  List<String> words(String k) {
    final v = raw[k];
    if (v is! List ||
        v.isEmpty ||
        v.any((e) => e is! String || !RegExp(r"^[a-z][a-z'-]*$").hasMatch(e))) {
      p.add('$k must be a list of lower-case words');
      return const [];
    }
    return v.cast<String>();
  }

  if (!packTargets.containsKey(pack)) return ['unknown pack $pack'];
  if (pack == 'roots') return _checkRoot(raw);
  final term = str('term').toLowerCase();
  final id = str('id');
  final en = str('en');
  final bn = str('bn');
  final hi = str('hi');
  final ex = str('ex').toLowerCase();
  if (term.isNotEmpty && id != packId(term)) {
    p.add('id must be ${packId(term)}');
  }
  if (en.isNotEmpty && !_latin.hasMatch(en)) p.add('en not English');
  if (bn.isNotEmpty && !onlyScript(bn, _bengali)) {
    p.add('bn not Bengali script');
  }
  if (hi.isNotEmpty && !onlyScript(hi, _devanagari)) p.add('hi not Devanagari');
  checkTranslations(raw['tr'], p);
  final exams = raw['exams'];
  if (exams != null &&
      (exams is! List || exams.any((e) => !wordExams.contains(e)))) {
    p.add('exams must be from $wordExams');
  }
  final parts = term.split(' ').where((w) => w.isNotEmpty).toList();
  switch (pack) {
    case 'idioms' || 'phrasal':
      if (parts.length < 2) p.add('term must be a phrase');
      // The example must use the phrase: its longest word must appear.
      // Placeholders such as "one's" / "someone's" change in use
      // ("his heels"), so they are skipped.
      final content = parts.where((w) => !w.contains("'")).toList();
      if (content.isNotEmpty && ex.isNotEmpty) {
        final longest = content.reduce((a, b) => b.length > a.length ? b : a);
        if (!ex.contains(_stem(longest))) p.add('example does not use term');
      }
    case 'ows' || 'spelling':
      if (parts.length != 1) p.add('term must be one word');
      if (term.isNotEmpty && ex.isNotEmpty && !ex.contains(_stem(term))) {
        p.add('example does not use term');
      }
      if (pack == 'ows') {
        final clue = str('clue');
        if (clue.isNotEmpty && !_latin.hasMatch(clue)) {
          p.add('clue not English');
        }
        if (clue.toLowerCase().contains(term)) {
          p.add('clue gives away the term');
        }
      } else {
        final wrong = words('wrong');
        if (wrong.contains(term)) p.add('a misspelling equals the term');
        if (wrong.length > 3) p.add('at most 3 misspellings');
      }
    case 'confusables':
      final ws = words('words');
      if (ws.length < 2 || ws.length > 3) p.add('needs 2-3 words');
      for (final w in ws) {
        if (ex.isNotEmpty && !ex.contains(_stem(w))) {
          p.add('example does not use "$w"');
        }
      }
      if (ws.isNotEmpty && term != ws.join(' vs ')) {
        p.add('term must be "${ws.join(' vs ')}"');
      }
  }
  return p;
}

/// Problems with a whole pack file; with [previous], existing items must
/// keep their order and the version must go up.
List<String> checkPackFile(Object? raw, String pack, {Object? previous}) {
  if (raw is! Map) return ['file is not a JSON object'];
  final out = <String>[];
  final version = raw['version'];
  if (version is! int) out.add('version must be an integer');
  final items = raw['items'];
  if (items is! List) return [...out, 'items must be a list'];
  final seen = <String>{};
  for (var i = 0; i < items.length; i++) {
    final e = items[i];
    final id = e is Map && e['id'] is String ? e['id'] as String : '#$i';
    for (final problem in checkPackItem(e, pack)) {
      out.add('$id: $problem');
    }
    if (!seen.add(id)) out.add('$id: duplicate id');
  }
  if (previous is Map && previous['items'] is List) {
    final pv = previous['version'];
    if (version is int && pv is int && version <= pv) {
      out.add('version must be higher than $pv');
    }
    final old = [
      for (final e in previous['items'] as List)
        if (e is Map) e['id'],
    ];
    for (var i = 0; i < old.length; i++) {
      if (i >= items.length ||
          items[i] is! Map ||
          (items[i] as Map)['id'] != old[i]) {
        out.add('existing items must stay in order (position $i, "${old[i]}")');
        break;
      }
    }
  }
  return out;
}

/// Word Roots lesson: a Greek/Latin root, its meaning and origin, an
/// original short lesson note, and 4-8 derived words with meanings.
///   {id, term, forms, origin, unit, en, bn, hi, tr?, note, ex,
///    words: [{word, en, bn, hi, tr?}]}
List<String> _checkRoot(Map raw) {
  final p = <String>[];
  String str(Map m, String k, [String at = '']) {
    final v = m[k];
    if (v is! String || v.trim().isEmpty) {
      p.add('$at$k missing');
      return '';
    }
    return v.trim();
  }

  void meanings(Map m, String at) {
    final en = str(m, 'en', at);
    final bn = str(m, 'bn', at);
    final hi = str(m, 'hi', at);
    if (en.isNotEmpty && !_latin.hasMatch(en)) p.add('${at}en not English');
    if (bn.isNotEmpty && !onlyScript(bn, _bengali)) {
      p.add('${at}bn not Bengali script');
    }
    if (hi.isNotEmpty && !onlyScript(hi, _devanagari)) {
      p.add('${at}hi not Devanagari');
    }
    final tp = <String>[];
    checkTranslations(m['tr'], tp);
    p.addAll(tp.map((e) => '$at$e'));
  }

  final term = str(raw, 'term').toLowerCase();
  if (term.isNotEmpty && str(raw, 'id') != packId(term)) {
    p.add('id must be ${packId(term)}');
  }
  final origin = str(raw, 'origin');
  if (origin.isNotEmpty &&
      !const {'Latin', 'Greek', 'Old English', 'French'}.contains(origin)) {
    p.add('origin must be Latin, Greek, Old English or French');
  }
  final unit = str(raw, 'unit');
  if (unit.isNotEmpty && !rootUnits.contains(unit)) {
    p.add('unknown unit "$unit"');
  }
  str(raw, 'note');
  meanings(raw, '');
  final formsRaw = raw['forms'];
  final forms = <String>{
    if (term.isNotEmpty) term.replaceAll('-', ''),
    if (formsRaw is List)
      for (final f in formsRaw)
        if (f is String && f.trim().isNotEmpty)
          f.trim().toLowerCase().replaceAll('-', ''),
  };
  final words = raw['words'];
  if (words is! List || words.length < 4 || words.length > 8) {
    p.add('needs 4-8 derived words');
    return p;
  }
  final seen = <String>{};
  for (final w in words) {
    if (w is! Map) {
      p.add('word not an object');
      continue;
    }
    final word = str(w, 'word', 'word ').toLowerCase();
    if (word.isEmpty) continue;
    if (!seen.add(word)) p.add('$word: duplicate');
    if (!RegExp(r'^[a-z-]+$').hasMatch(word)) {
      p.add('$word: not one lower-case word');
    }
    if (!forms.any(word.contains)) p.add('$word: does not contain the root');
    meanings(w, '$word: ');
  }
  final ex = str(raw, 'ex').toLowerCase();
  if (ex.isNotEmpty && !seen.any((w) => ex.contains(_stem(w)))) {
    p.add('example uses none of the derived words');
  }
  return p;
}
