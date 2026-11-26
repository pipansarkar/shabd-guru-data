// Tags words with a level (1 basic, 2 intermediate, 3 advanced) from how
// common they are in real English, using the free Datamuse API. No AI.
//
//   dart run levels.dart
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

Future<void> main() async {
  final file = File('words.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  var tagged = 0;
  for (final w in (data['words'] as List).cast<Map<String, dynamic>>()) {
    if (w['lvl'] != null) continue;
    final f = await datamuse.frequency(w['word'] as String);
    if (f == null) break; // Datamuse unavailable: try again tomorrow.
    w['lvl'] = levelForFrequency(f);
    tagged++;
  }
  if (tagged == 0) {
    stdout.writeln('All words already have a level.');
    return;
  }
  data['version'] = (data['version'] as int) + 1;
  data['updated'] = todayIst();
  file.writeAsStringSync(formatWords(data));
  addCommitLine('Levels: tagged $tagged words');
  stdout.writeln('Tagged $tagged words.');
}
