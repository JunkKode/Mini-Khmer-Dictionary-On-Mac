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
"""

INDEXES = """
CREATE INDEX entries_word ON entries(word);
CREATE INDEX entries_ord  ON entries(ord);
"""


def clean(value):
    return (value or "").strip()


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
    db.executescript(INDEXES)
    db.commit()
    db.execute("VACUUM")
    db.close()

    size = os.path.getsize(DB_PATH) / (1024 * 1024)
    print(f"wrote {len(rows):,} entries to {DB_PATH} ({size:.1f} MB)")


if __name__ == "__main__":
    build()
