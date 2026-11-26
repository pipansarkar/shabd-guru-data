// Upcoming exam dates for the app's countdown, copied daily from the
// Speed Math data repo (which keeps them current). No AI involved.
//
//   dart run exams.dart
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'word_check.dart';

const source =
    'https://raw.githubusercontent.com/pipansarkar/speed-maths-data/main/exam_patterns.json';

/// Exam families relevant to vocabulary (English sections).
const families = {'bank', 'ssc', 'cat', 'cuet', 'upsc', 'railway'};

Future<void> main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  Map<String, dynamic> patterns;
  try {
    final res = await (await client.getUrl(Uri.parse(source))).close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    patterns =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('Could not read exam dates: $e; no changes.');
    return;
  } finally {
    client.close();
  }

  final today = todayIst();
  final upcoming = [
    for (final e in (patterns['examDates'] as List? ?? const []))
      if (e is Map &&
          e['date'] is String &&
          (e['date'] as String).compareTo(today) >= 0 &&
          families.contains(e['exam']))
        {
          'exam': e['exam'],
          'name': e['name'],
          'date': e['date'],
          'tentative': e['tentative'] == true,
        },
  ]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

  final file = File('exams.json');
  final old = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{'version': 0, 'exams': <Object>[]};
  if (jsonEncode(old['exams']) == jsonEncode(upcoming)) {
    stdout.writeln('Exam dates unchanged.');
    return;
  }
  final out = {
    'version': (old['version'] as int) + 1,
    'updated': today,
    'exams': upcoming,
  };
  final problems = checkExamsFile(out);
  if (problems.isNotEmpty) {
    stderr.writeln('Not publishing:\n${problems.join('\n')}');
    exit(1);
  }
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(out)}\n',
  );
  addCommitLine('Exam dates: ${upcoming.length} upcoming');
  stdout.writeln('Wrote ${upcoming.length} upcoming exams.');
}
