# Daily word update: instructions for the scheduled agent

Goal: grow `words.json` (Shabd Guru's live word list) with high-frequency
exam vocabulary for Bank (IBPS/SBI PO & Clerk, RBI), SSC (CGL/CHSL/CPO),
CAT and CUET aspirants, with English, Bengali and Hindi meanings.
**Publish directly to `main`**; there is no human review, so every check
below is mandatory.

Installed apps download `words.json` within hours of a push.

## 1. Set up
- Clone `pipansarkar/shabd-guru-data` (this repo).
- Make sure the Dart SDK is on PATH (`dart --version`); if not, install it
  (e.g. `git clone https://github.com/flutter/flutter.git -b stable --depth 1`
  and use `flutter/bin/dart`).
- Save a copy of the current file: `cp words.json /tmp/previous.json`.

## 2. Decide how many words
- Target: **2,000 words**. If `words.json` already has 2,000 or more, stop
  (no commit).
- Otherwise add **25 new words** this run (fewer if that would pass 2,000).

## 3. Choose the words
- Pick words that recur in previous Bank, SSC, CAT and CUET English papers
  (synonym/antonym, cloze, error-spotting and reading-comprehension
  questions), and words common in newspaper editorials. Most frequent and
  useful first.
- Use your own knowledge plus searches of several past-paper analyses to
  judge frequency. Select individual words only; never copy a published
  word list wholesale or in its order.
- Skip any word whose `id` is already in the file, and near-duplicates
  (e.g. don't add "abatement" when "abate" exists). Search the file before
  adding.

## 4. Write each entry (all original writing)
Append to the end of `words`; **never edit, reorder or remove existing
entries** (the validator rejects it). Fields:

| field | rule |
|---|---|
| `id` | the word in lower case (spaces → `-`) |
| `word` | headword, lower case |
| `pos` | `noun`, `verb`, `adjective` or `adverb` (the sense exams test) |
| `en` | short plain-English meaning, under 12 words, own wording |
| `bn` | 1–3 natural Bengali equivalents, comma-separated, Bengali script |
| `hi` | 1–3 natural Hindi equivalents, comma-separated, Devanagari |
| `syn` | 3–4 synonyms, same part of speech, exam-relevant |
| `ant` | 2–3 antonyms, same part of speech |
| `ex` | one original sentence using the word, Indian context welcome, ≤ 20 words |
| `trick` | a short memory trick (root, sound-alike or picture) |
| `exams` | subset of `bank`, `ssc`, `cat`, `cuet`, `upsc`: where the word fits |

Never copy definitions, examples or tricks from dictionaries (Oxford,
Merriam-Webster, Cambridge…), Blackbook, SP Bakshi, Norman Lewis or coaching
PDFs. Never add a specific paper tag such as "SBI PO 2024".

## 5. Self-review (mandatory, because no human checks this)
Re-read every new entry and fix anything that fails:
- The Bengali and Hindi meanings are what a native speaker would actually
  say for this sense, spelt correctly. Bengali must not be Hindi written in
  Bengali script. If unsure of a translation, choose a simpler word you are
  sure of.
- Every synonym really can replace the word in the example sentence, and
  every antonym is a true opposite, in the same part of speech.
- The example uses the word correctly and is not offensive, political or
  about real living people.
- The memory trick is not misleading about the spelling or meaning.

## 6. Validate (must pass)
```
dart run validate.dart words.json /tmp/previous.json
```
It checks every field, scripts, overlaps, that the example uses the word,
that existing words are unchanged in order, and that `version` went up.
Bump `version` by 1 and set `updated` to today's date (YYYY-MM-DD) before
running it. Fix and re-run until it prints `OK`.

## 7. Publish
- If you added nothing, stop: no empty commits.
- Add a line to the top of `CHANGELOG.md`:
  `- vN (YYYY-MM-DD): +25 words: first, second, ... (total T)`.
- Commit to `main` with message `Words vN: +25 (total T)` and push.
- CI re-runs the validator and reverts the commit if it fails; check the
  Actions run went green.
