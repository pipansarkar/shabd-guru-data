// Usage: dart run validate.dart words.json [previous_words.json]
// Rules: word_check.dart (generated from the app; do not edit here).
import 'dart:convert';
import 'dart:io';

import 'word_check.dart';

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
