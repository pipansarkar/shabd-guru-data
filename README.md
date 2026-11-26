# Shabd Guru — live word list

`words.json` is the word list used by the Shabd Guru app. Installed apps
download it within hours of a change (no app release needed).

- **Updated automatically**: a scheduled agent appends 25 words a day until
  the list reaches 2,000 words, following `AGENT.md`, and pushes to `main`.
- **Validated twice**: the agent runs `validate.dart` before pushing, and the
  GitHub Action re-runs it on every push and reverts any push that fails.
- **Safe in the app**: the app ignores files that are older, smaller or
  unreadable, and skips any single entry that breaks the rules.

Rules: existing words are never edited, reordered or removed (users'
progress depends on them); `version` goes up with every change.

    dart run validate.dart words.json [previous_words.json]

`validate.dart` is generated from the app's `lib/data/word_check.dart`
by `vocab_builder/tool/sync_validator.sh`; edit the app copy.

All meanings, translations, examples and memory tricks are original.
