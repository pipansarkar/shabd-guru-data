# Shabd Guru — live word list

`words.json` is the word list used by the Shabd Guru app. Installed apps
download it within hours of a change (no app release needed).

## Fully automatic, free
- `.github/workflows/daily-words.yml` runs every day at 06:00 IST and adds
  25 words until the list reaches 2,000, using the free Gemini API (Google
  AI Studio) and free GitHub Actions minutes (public repo).
- `generate.dart`: suggests frequent exam words -> writes cards in batches
  of 5 -> a second reviewer pass corrects Bengali, Hindi, synonyms and
  antonyms -> drops any card that breaks the rules.
- Model names are discovered at run time (newest free Flash first); set the
  repository variable `GEMINI_MODEL` to force one.

Setup, once: add the repository secret `GEMINI_API_KEY`
(https://aistudio.google.com/apikey). Run it by hand from the Actions tab
("Daily words" -> Run workflow).

## Safety (nobody reviews by hand)
1. The daily job validates before pushing (`validate.dart`, same rules as
   the app).
2. `validate.yml` re-validates manual pushes and reverts any that fail.
3. The app ignores files that are older, smaller or unreadable, and skips
   any single entry that breaks the rules.

Existing words are never edited, reordered or removed (users' progress
depends on them); `version` goes up with every change.

`word_check.dart` is generated from the app's `lib/data/word_check.dart` by
`vocab_builder/tool/sync_validator.sh`; edit the app copy.
