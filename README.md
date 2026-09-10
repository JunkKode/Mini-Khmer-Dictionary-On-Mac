# Mini Khmer Dictionary

A macOS menu bar dictionary for Khmer, built on the Chuon Nath dictionary.
Click the menu bar icon for a popover with search, a word list, and a reading
pane; copying is always explicit.

Search accepts Khmer script or Latin letters — `bong` finds បង, `domlai` and
`tomlai` both find តម្លៃ.

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
| `Tools/` | CSV → SQLite pipeline |
| `Data/` | Source CSV |

`Tools/khmer_romanize.py` is the source of truth for romanized search: it
transcribes each headword at build time and reduces it to a fuzzy key.
`RomanizedSearch.fuzzyKey(_:)` in Swift mirrors that reduction for what the user
types, so the two must be changed together.

`Tools/khmer_frequency.py` counts how often each headword appears in the
dictionary's own definitions, which is what breaks ties between romanized
candidates that sound equally close.

## Continuous integration

`.github/workflows/build.yml` regenerates the database and builds the app
unsigned on every push, uploading the result as a workflow artifact.
