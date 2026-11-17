#!/usr/bin/env python3
"""Convert the Chuon Nath CSV export into the read-only SQLite database the app ships.

Usage:  python3 Tools/build_dictionary_db.py
        (run from the repository root)

Rows in the CSV are sense-level: a row that carries `t_main` starts a new entry and
every following row with the same `t_ref` is an additional sense of it.
"""

import csv
import json
import os
import sqlite3
import sys

from khmer_frequency import count_word_uses
from khmer_romanize import fuzzy_key, romanize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "Data", "khmer_dict.csv")
CORPUS_PATH = os.path.join(ROOT, "Data", "khmer_corpus.tsv")
PAIRS_PATH = os.path.join(ROOT, "Data", "khmer_bigrams.tsv")
DB_PATH = os.path.join(ROOT, "Mini Khmer Dictionary", "Resources", "khmer_dict.sqlite3")

SCHEMA = """
PRAGMA journal_mode = DELETE;
DROP TABLE IF EXISTS entries;
CREATE TABLE entries (
    id       INTEGER PRIMARY KEY,
    ord      INTEGER NOT NULL,
    word     TEXT    NOT NULL,
    headword TEXT    NOT NULL,
    pron     TEXT    NOT NULL,
    pos      TEXT    NOT NULL,
    level    INTEGER NOT NULL,
    gloss    TEXT    NOT NULL,
    senses   TEXT    NOT NULL,
    roman    TEXT    NOT NULL,
    rkey     TEXT    NOT NULL,
    freq     INTEGER NOT NULL
);
DROP TABLE IF EXISTS corpus_words;
-- Words from Data/khmer_corpus.tsv that are not headwords: in everyday use
-- (meant = '') or a common misspelling of `meant`. Read whole by the spell
-- checker, never searched, so it needs no index beyond its key.
CREATE TABLE corpus_words (
    word  TEXT    PRIMARY KEY,
    freq  INTEGER NOT NULL,
    meant TEXT    NOT NULL
) WITHOUT ROWID;
DROP TABLE IF EXISTS word_pairs;
-- From Data/khmer_bigrams.tsv: the words that most often follow `context`,
-- as "word score" pairs separated by tabs, best first. Read whole by the
-- spell checker for ranking corrections and predicting the next word.
CREATE TABLE word_pairs (
    context TEXT PRIMARY KEY,
    next    TEXT NOT NULL
) WITHOUT ROWID;
"""

INDEXES = """
CREATE INDEX entries_word ON entries(word);
CREATE INDEX entries_ord  ON entries(ord);
"""


def clean(value):
    return (value or "").strip()


def load_pairs():
    """Rows for word_pairs, or none when the corpus hasn't been built."""
    if not os.path.exists(PAIRS_PATH):
        return []
    rows = []
    with open(PAIRS_PATH, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            context, _, rest = line.rstrip("\n").partition("\t")
            if context and rest:
                rows.append((context, rest))
    return rows


def load_corpus():
    """Headword usage and extra words from the corpus, if it has been built.

    Data/khmer_corpus.tsv is produced by Tools/build_corpus_lexicon.sh from a
    40M-word Khmer web corpus. Without it, the database still builds, with
    frequencies counted from the dictionary's own definitions instead.
    """
    if not os.path.exists(CORPUS_PATH):
        return None, []
    usage = {}
    extra = []
    with open(CORPUS_PATH, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            kind, word, count, meant = line.rstrip("\n").split("\t")
            if kind == "h":
                usage[word] = int(count)
            elif kind == "w":
                extra.append((word, int(count), ""))
            elif kind == "m":
                extra.append((word, int(count), meant))
    return usage, extra


def build():
    if not os.path.exists(CSV_PATH):
        sys.exit(f"missing source CSV: {CSV_PATH}")

    entries = {}
    order = []

    with open(CSV_PATH, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            ref = clean(row["t_ref"])
            if not ref:
                continue
            entry = entries.get(ref)
            if entry is None:
                word = clean(row["t_subword"]) or clean(row["t_main"])
                if not word:
                    continue
                entry = {
                    "id": int(ref),
                    "word": word,
                    "headword": clean(row["t_main"]) or word,
                    "pron": clean(row["t_pron"]),
                    "pos": clean(row["t_pos"]),
                    "level": int(clean(row["t_level"]) or 1),
                    "senses": [],
                }
                entries[ref] = entry
                order.append(ref)

            definition = clean(row["t_exp"])
            example = clean(row["t_exam"])
            note = " ".join(part for part in (clean(row["t_notes"]), clean(row["t_remark"])) if part)
            if not (definition or example or note):
                continue
            entry["senses"].append(
                {
                    "n": clean(row["t_poly"]),
                    "p": clean(row["t_pos"]),
                    "d": definition,
                    "e": example,
                    "note": note,
                }
            )

    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    db = sqlite3.connect(DB_PATH)
    db.executescript(SCHEMA)

    # How often each headword appears in the dictionary's own prose, used to
    # break ties between romanized matches that sound equally close.
    vocabulary = sorted({entries[ref]["word"] for ref in order})
    corpus = [
        " ".join(part for sense in entries[ref]["senses"]
                 for part in (sense["d"], sense["e"], sense["note"]) if part)
        for ref in order
    ]
    frequency = dict(zip(vocabulary, count_word_uses(vocabulary, corpus)))

    # Real usage beats the dictionary's prose when it is available. A word the
    # corpus never saw but the definitions use still outranks one never used.
    usage, corpus_words = load_corpus()
    if usage is not None:
        frequency = {
            word: usage.get(word) or (1 if frequency.get(word) else 0)
            for word in vocabulary
        }

    rows = []
    for position, ref in enumerate(order):
        entry = entries[ref]
        senses = entry["senses"]
        gloss = next((s["d"] for s in senses if s["d"]), "").rstrip(" :")
        if len(gloss) > 140:
            gloss = gloss[:140].rstrip() + "\u2026"
        roman = romanize(entry["word"])
        rows.append(
            (
                entry["id"],
                position,
                entry["word"],
                entry["headword"],
                entry["pron"],
                entry["pos"],
                entry["level"],
                gloss,
                json.dumps(senses, ensure_ascii=False, separators=(",", ":")),
                roman,
                fuzzy_key(roman),
                frequency.get(entry["word"], 0),
            )
        )

    db.executemany(
        "INSERT INTO entries (id, ord, word, headword, pron, pos, level, gloss, senses, roman, rkey, freq)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    headwords = set(vocabulary)
    db.executemany(
        "INSERT OR IGNORE INTO corpus_words (word, freq, meant) VALUES (?, ?, ?)",
        [row for row in corpus_words if row[0] not in headwords],
    )
    pairs = load_pairs()
    db.executemany("INSERT OR IGNORE INTO word_pairs (context, next) VALUES (?, ?)", pairs)
    db.executescript(INDEXES)
    db.commit()
    db.execute("VACUUM")
    db.close()

    size = os.path.getsize(DB_PATH) / (1024 * 1024)
    print(f"wrote {len(rows):,} entries to {DB_PATH} ({size:.1f} MB)")
    if usage is None:
        print(f"note: {CORPUS_PATH} not found; frequencies come from the definitions")
    else:
        print(f"with corpus usage for {len(usage):,} headwords, {len(corpus_words):,} corpus words"
              f" and word pairs for {len(pairs):,} words")


if __name__ == "__main__":
    build()
