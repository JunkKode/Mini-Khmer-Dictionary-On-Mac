# Mini Khmer Dictionary

A macOS menu bar dictionary for Khmer, built on the Chuon Nath dictionary.
Click the menu bar icon for a popover with search, a word list, and a reading
pane; copying is always explicit.

Search accepts Khmer script or Latin letters — `bong` finds បង, `domlai` and
`tomlai` both find តម្លៃ.

## Tabs

| Tab | ⌘ | What it does |
| --- | --- | --- |
| Look Up | 1 | Search in Khmer or Latin letters; how common each word is, words that often follow it, Saved and Recent lists, a word of the day |
| Check Spelling | 2 | Underlines mistakes with ranked fixes; suggests the word you're typing (⇥ to accept) |
| Calculator | 3 | Simple keypad, Smart formulas, and a Grid with Excel-style copy/paste and a fill handle |
| Calendar | 4 | A month in both calendars: lunar days, holy days (moons) and public holidays, checked against Google |
| Currency | 5 | Converts one amount — or a mix like `$12 + 5000៛` — into several currencies at once, with a grey `1,000,000` preview while you type; drag a row by its flag to reorder, right-click to delete; editable rates or **Update Online** |
| Khmer No. | 6 | Numbers in Khmer words (also as riel or dollars) and Khmer digits |
| Gold & Units | 7 | ជី, ដំឡឹង, ហ៊ុន, លី, gold value from today's price, length, land, volume, temperature |
| Loan | 8 | Equal, declining or flat-rate repayments, with a copyable schedule |
| Date | 9 | Khmer solar and lunar dates (ចន្ទគតិ, BE year, animal year, ស័ក), days between dates, adding days |

### Look up selected text

Select Khmer text in any app and press **⌥Space**: a card with the
definition opens next to the pointer, and the app you're in stays in front.
A phrase is split into words; click one, or use the arrow keys, to see it.
A known misspelling shows the word meant (តំលៃ → តម្លៃ). Press ⏎ to open the
word in the full dictionary, ⌘C to copy it (⇧⌘C with its definition), ⌘S to
save it, and Escape to close the card. With nothing selected, ⌥Space opens
the popover as before.

To read the selection, the app presses ⌘C for you and then puts your
clipboard back. Pressing keys for you needs the Accessibility permission
(System Settings › Privacy & Security › Accessibility). macOS asks for it the
first time you use ⌥Space; until it's given, the menu bar icon's right-click
menu has **Allow ⌥Space to Look Up Selected Text…**. The code is in
`Support/SelectionReader.swift` and `Support/QuickLookupPanel.swift`.

### Clipboard history

Press **⇧⌘V** anywhere for what you've copied: text (with its formatting),
images and files, newest first. Click an item, or press ⏎, and it's pasted
where you were typing and the popup closes; ⌥⏎ pastes text without
formatting, and ⌘1–⌘9 paste the first nine. Clicking outside or Escape
closes it. Type to search.

- **Pin** (⌘P) keeps an item at the top of the list.
- **Favorite** (⌘S) keeps an item in the Favorites list.
- Pinned and favorite items are never removed by **Clear All**, nor when the
  history passes its 60 other items. ⌘⌫ deletes the highlighted item.
- **Keep open** leaves the popup on screen after pasting, so you can paste
  several items in a row: click one, click in your document, click the next.
  Open it this way with **⇧⌘X**, or switch it with the pin button at the top
  or ⌘D. Clicking elsewhere doesn't close it; Escape or the shortcut does.
  Drag the top bar to move it off the text behind it.

The history is saved in the app's container and survives restarts. Items
that password managers mark as concealed are never recorded, nor is the copy
the ⌥Space look-up makes. Turn it off, or clear it, from the menu bar icon's
right-click menu. Pasting for you uses the same Accessibility permission as
⌥Space; without it, the chosen item is only copied. ⇧⌘V is taken
system-wide, so apps that use it (often "paste as plain text") won't get it
while Mini Khmer Dictionary is running; pick other keys in Settings if
that gets in the way.

### Settings

**Settings…** (⌘, in the popover, the menu bar icon's right-click menu, or the
gear in the clipboard popup) changes the three shortcuts: click one and press the
new keys. A shortcut needs ⌘, ⌥ or ⌃ (or a function key), can't be one every
app uses such as ⌘C, and is refused if another app already holds it. Each
can also be turned off or reset. Settings also switches clipboard history on
or off and clears it. Shortcuts
are in `Support/Hotkeys.swift`.

### Calendar and holidays

The Khmer lunar calendar (`Shared/KhmerLunarCalendar.swift`) is the
traditional calculation, as in the open-source momentkh; it works offline for
1900–2200. Holidays come from two sources: fixed dates and lunar rules
(`Shared/KhmerHolidays.swift`), and Google's public "Holidays in Cambodia"
calendar, synced weekly and cached, which follows the government's yearly
announcements. Each holiday is marked *Matches Google*, *Google* (e.g. a
special day off) or *Calculated*, with a note where the two disagree. For
2021–2027 every lunar holiday in Google's list falls on the day the
calculation gives.

### Widget

The **Khmer Calendar** widget (target `KhmerCalendarWidget`, macOS 14+) shows
today in both calendars and the next public holidays. Add it from the
desktop's Edit Widgets. It uses the calculated holidays, since widgets don't
go online.

### Holy-day image

Buddhist holy days (ថ្ងៃសីល) are marked with the `buddhist` image from
`Mini Khmer Dictionary/Assets.xcassets`. The widget can't read the app's
images, so it has its own small copy in `KhmerCalendarWidget/Assets.xcassets`;
replace both if you change it. Without the image, a meditating figure is
shown.

### Currency flags

Each currency shows a round flag from an image set in
`Mini Khmer Dictionary/Assets.xcassets` named `flag-` plus its code, e.g.
`flag-KHR`, `flag-USD`, `flag-KRW`. Any square image works (it is cropped to a
circle) and it appears in the list and in the searchable currency pickers.
Without one, the currency symbol is shown in a coloured circle. The 38
currencies, grouped by region, are listed in `Currency.all` in
`Model/Calculator/ExchangeRates.swift`:

KHR USD THB VND LAK MYR SGD IDR PHP MMK BND · CNY JPY KRW HKD TWD INR ·
EUR GBP CHF SEK NOK DKK PLN RUB TRY · CAD MXN BRL AUD NZD ·
AED SAR QAR KWD ILS EGP ZAR

The appearance button at the top right switches between light, dark and the
system setting (also in the menu bar icon's right-click menu).

Formulas can use the tools too: `KHMERWORDS`, `KHMERMONEY`, `KHMERDIGITS`,
`FX`, `PMT`, `DATE`, `DAYS`, `EDATE` and `LUNAR`.

In the Grid, ⌘C marks the copied cells with a moving border and ⌘V pastes
formulas with their references moved; right-click or ⇧⌘V pastes values only.
Drag the dot at a selection's corner to fill: it previews the result while
dragging, continues series (1, 2, 3; Item 1, Item 2; months and weekdays in
English or Khmer), copies anything else, and with ⌥ makes a single number
count up.

## Spell checking

The **Check Spelling** tab (⌘2) checks Khmer text against the dictionary. Khmer
has no spaces between words, so each run of text is first split into the fewest
dictionary words that cover it, and whatever can't be covered is flagged.
Problems are underlined in red (not in the dictionary) or orange (typed in a
non-standard order, or a variant such as ្ត for ្ដ), with suggestions.

To check text in another app, select it and choose **Services › Check Khmer
Spelling** from the app menu or the right-click menu. **Look Up in Khmer
Dictionary** works the same way. You can give either one a keyboard shortcut in
System Settings › Keyboard › Keyboard Shortcuts › Services.

The engine is `Model/KhmerSpellChecker.swift`. Words added with "Add to
Dictionary" are stored in user defaults under `learnedWords`.

### What the corpus adds

The dictionary alone doesn't know how often words are used, nor the thousands
of names, places and loanwords it never catalogued (អាមេរិក, ស្មាតហ្វូន).
`Data/khmer_corpus.tsv` fills that in from a 40M-word Khmer web corpus:

- **Usage counts** for every headword (and the spellings that differ from it
  only in typing order or ្ត/្ដ), which rank suggestions and break ties in
  segmentation and romanized search.
- **Words the dictionary lacks**, accepted when they are common and not a
  cheap edit away from a far more common dictionary word.
- **Common misspellings** with the word meant — តំលៃ → តម្លៃ, អោយ → ឱ្យ,
  ពត៌មាន → ព័ត៌មាន — so they are recognised outright, even inside a longer
  run of text.
- **Word pairs** (`Data/khmer_bigrams.tsv`): which words follow which, used to
  rank corrections by the words around them, to complete the word being
  typed, and to predict the next one.

Web text is full of misspellings, so its words are never trusted just for
being frequent: each one is compared with its closest dictionary words using
the checker's own confusion costs. See `Tools/CorpusLexicon/main.swift` for
the rules.

The file is checked in; regenerating it needs the corpus database
(`khmer-text-data/khmer.db`, not in the repository):

```bash
Tools/build_corpus_lexicon.sh
python3 Tools/build_dictionary_db.py
```

`Tools/test_spell_checker.sh` runs the checker's tests against the built
database; pass a corpus text file to also measure flag rate and correction
accuracy.

Requires macOS 13 or later.

## Building

The SQLite database the app ships is generated from `Data/khmer_dict.csv`, and
is not stored in the repository. After cloning:

```bash
python3 Tools/build_dictionary_db.py
```

Then open `Mini Khmer Dictionary.xcodeproj` and run. Regenerate whenever the CSV
changes; nothing else depends on Python at runtime.

## Layout

| Path | What it holds |
| --- | --- |
| `Mini Khmer Dictionary/Model` | SQLite access, search ranking, view model |
| `Mini Khmer Dictionary/Views` | Popover, list, reading pane, split handle |
| `Mini Khmer Dictionary/Support` | Status item and popover hosting |
| `Tools/` | CSV → SQLite pipeline, corpus lexicon builder, tests |
| `Data/` | Source CSV and the corpus lexicon |

`Tools/khmer_romanize.py` is the source of truth for romanized search: it
transcribes each headword at build time and reduces it to a fuzzy key.
`RomanizedSearch.fuzzyKey(_:)` in Swift mirrors that reduction for what the user
types, so the two must be changed together.

Ties between romanized candidates that sound equally close are broken by how
often each headword is used in the corpus. Without `Data/khmer_corpus.tsv`,
`Tools/khmer_frequency.py` falls back to counting uses in the dictionary's own
definitions.

## Continuous integration

`.github/workflows/build.yml` regenerates the database and builds the app
unsigned on every push, uploading the result as a workflow artifact.
