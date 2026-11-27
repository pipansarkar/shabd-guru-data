# Shabd Guru — live content

Content for the Shabd Guru app. Installed apps download it within hours of
a change (no app release needed).

| file | what | updated by |
|---|---|---|
| `words.json` | main word list (grows to 2,000) | `generate.dart` |
| `editorial.json` | Daily Editorial Words, last 30 days | `editorial.dart` |
| `archive/editorial-YYYY-MM.json` | every editorial day, kept | `editorial.dart` |
| `idioms.json` | idioms & phrases (grows to 600) | `packs.dart` |
| `ows.json` | one word substitution (800) | `packs.dart` |
| `phrasal.json` | phrasal verbs (300) | `packs.dart` |
| `spelling.json` | commonly misspelt words (300) | `packs.dart` |
| `confusables.json` | confusing word groups (200) | `packs.dart` |
| `roots.json` | Word Roots course: Greek/Latin roots by theme (150) | `packs.dart` |

Every card has English, Bengali and Hindi, plus `tr` with Marathi, Telugu,
Tamil, Gujarati, Urdu, Kannada, Odia, Malayalam, Punjabi and Assamese
(`translate.dart` fills these in for words; packs are written with all 12).
`levels.dart` tags words 1 basic / 2 intermediate / 3 advanced from Datamuse
word frequency.

The Word Roots course follows the general roots-by-theme method of books
like *Word Power Made Easy*, but every lesson is original writing; no text,
lesson structure or word list is taken from any book.

## Fully automatic, free
`.github/workflows/daily-content.yml` runs every day at 06:00 IST:
1. **Editorial words**: reads editorial RSS feeds (The Hindu, The Indian
   Express, Hindustan Times, Mint), picks 10 exam-worthy words that appear
   in today's headlines/summaries and writes original cards for them.
   Only each article's headline and link are published; editorial text is
   never copied.
2. **Words**: suggests frequent exam words, ranks them by real-world
   frequency, writes 25 cards.
3. **Levels**, **topic packs** (one pack a day, rotating) and
   **translations** use the rest of the free daily quota.

Cards are written by the free Gemini API (Google AI Studio), corrected by a
second reviewer pass, synonyms are checked against the free
[Datamuse API](https://www.datamuse.com/api/) (antonyms that it lists as
synonyms are removed), and every card must pass `word_check.dart`.
Gemini model names are discovered at run time; the free tier allows about
20 requests per model per day (each job has its own cap of 16).

Setup, once: repository secret `GEMINI_API_KEY`
(https://aistudio.google.com/apikey). From 1 Feb 2027 Datamuse needs a free
key too: request one from Datamuse and add secret `DATAMUSE_API_KEY`
(without it the synonym check is skipped, the run still works).
Run by hand: Actions → "Daily content" → Run workflow.

## Safety (nobody reviews by hand)
1. Each job validates before writing, and the workflow re-validates every
   file against the published copy before pushing (`validate.dart`).
2. `validate.yml` re-validates manual pushes and reverts any that fail.
3. The app ignores files that are older, smaller or unreadable, and skips
   any single entry that breaks the rules.

Existing words are never edited, reordered or removed (users' progress
depends on them); every file's `version` goes up with every change.

`word_check.dart` is generated from the app's `lib/data/word_check.dart` by
`vocab_builder/tool/sync_validator.sh`; edit the app copy.

Word data checks use the Datamuse API (https://www.datamuse.com/api/).
