# Translations

Cloro is in English and the eight most-spoken languages after it: Mandarin Chinese (`zh`), Hindi (`hi`), Spanish (`es`), Arabic (`ar`, right to left), French (`fr`), Bengali (`bn`), Portuguese (`pt`) and Russian (`ru`). The app follows the phone's language when it has it, otherwise English. **Settings → App → Language** picks one; each is listed in its own name.

## How it works

- The English text in the code is the key: `tr('Send feedback')`. A string without a translation shows in English, so nothing breaks while a translation is missing.
- Each language's text is in `app/assets/l10n/<code>.json`, mapping the English text to its translation.
- **Placeholders** stay as they are: `tr('Reading {title}', {'title': book.title})`. A translation may move a placeholder but must keep every one: `"Leyendo {title}"`, `"正在读《{title}》"`.
- **Counts** use `trn(n, '{n} card', '{n} cards')`, keyed by the plural ("other") form. In a language file the value is then a map of the language's plural forms, chosen by its own rules: `one`, `other` (Spanish, Hindi…); `one`, `few`, `many`, `other` (Russian); `zero`, `one`, `two`, `few`, `many`, `other` (Arabic); just `other` (Chinese).
- **Text kept in English in the data** (genres, habit anchors, scene names, league divisions) is stored in English and shown with `tr(value)`. Each one is listed in `app/lib/l10n/keys.dart` so the check below asks for it.
- **Dates** come from the language's own data: `localDate('MMMd')`. English uses British order ("2 Oct").
- **Not translated:** book text, AI prompts, font and voice names, plan names (Lite, Plus, Pro, Scholar), pronoun choices (other readers see them) and the voice sample (the natural voices are English).

## Adding or changing text

1. Write the English in the code inside `tr(...)`, `trn(...)` or (for a list kept in data) `tk(...)`/`keys.dart`. Keep it a literal: the check finds keys by reading the code.
2. List what's missing in a language:

   ```bash
   cd app && python3 tool/l10n_keys.py --missing assets/l10n/es.json
   ```

3. Add the translations to each `assets/l10n/<code>.json`.
4. Run the check. It fails if any language misses a string, drops or invents a placeholder, or has an empty or badly formed plural:

   ```bash
   flutter test test/l10n_test.dart
   ```

`test/widgets/accessibility_test.dart` also lays out every main screen in each language at 130% text size, to catch text that no longer fits.

**Tools** in `app/tool/` for converting a screen whose text isn't wrapped yet:
- `l10n_candidates.py` lists literals that look like text people read;
- `l10n_wrap.py` wraps the plain ones and lists those with `$` for hand conversion;
- `l10n_merge.py` joins split multi-line literals;
- `l10n_unconst.py` removes the `const` around wrapped text, reading `dart analyze --format=machine`.

Review what they change: a string that's data (a key, a file type, a font family) must stay unwrapped.

## Quality

The first translations were written along with the code and checked for meaning, placeholders and plural forms, but not by native speakers. Before a launch in a market, have a native speaker read that language's file in the app (a day's work each). The store listing needs translating too.
