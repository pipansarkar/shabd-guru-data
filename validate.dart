// Usage: dart run validate.dart FILE.json [PREVIOUS.json]
// Picks the rules by file name: words*.json, editorial*.json, exams*.json.
// Rules: word_check.dart (generated from the app; do not edit here).
import 'dart:convert';
import 'dart:io';

import 'word_check.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run validate.dart FILE.json [PREVIOUS.json]');
    exit(2);
  }
  final next = jsonDecode(File(args[0]).readAsStringSync());
  final prev = args.length > 1
      ? jsonDecode(File(args[1]).readAsStringSync())
      : null;
  final name = args[0].split('/').last;
  final problems = name.startsWith('editorial')
      ? checkEditorialFile(next, previous: prev)
      : name.startsWith('exams')
      ? checkExamsFile(next)
      : checkWordsFile(next, previous: prev);
  if (problems.isEmpty) {
    stdout.writeln('OK: $name version ${next['version']}');
    return;
  }
  problems.forEach(stderr.writeln);
  stderr.writeln('${problems.length} problem(s)');
  exit(1);
}
