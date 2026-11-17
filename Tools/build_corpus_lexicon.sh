#!/bin/bash
#
# Regenerate Data/khmer_corpus.tsv from the corpus prediction database.
#
#   Tools/build_corpus_lexicon.sh [path/to/khmer.db]
#
# The corpus database (khmer-text-data/khmer.db by default) is built from the
# OSCAR Khmer corpus and is far too large for the repository; its output,
# Data/khmer_corpus.tsv, is small and checked in, so only this step needs it.
#
# Needs the app database for the dictionary's headwords, so run
# Tools/build_dictionary_db.py first, then this, then build_dictionary_db.py
# again to load the result.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORPUS_DB="${1:-$PROJECT_DIR/khmer-text-data/khmer.db}"
APP_DB="$PROJECT_DIR/Mini Khmer Dictionary/Resources/khmer_dict.sqlite3"
OUTPUT="$PROJECT_DIR/Data/khmer_corpus.tsv"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -f "$CORPUS_DB" ]] || { echo "missing corpus database: $CORPUS_DB" >&2; exit 1; }
[[ -f "$APP_DB" ]] || { echo "missing $APP_DB — run Tools/build_dictionary_db.py first" >&2; exit 1; }

swiftc -O \
    -module-name CorpusLexicon \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -o "$BUILD_DIR/corpus-lexicon" \
    "$PROJECT_DIR/Mini Khmer Dictionary/Model/KhmerSpellChecker.swift" \
    "$PROJECT_DIR/Mini Khmer Dictionary/Model/KhmerWordPrediction.swift" \
    "$PROJECT_DIR/Tools/CorpusLexicon/main.swift"

"$BUILD_DIR/corpus-lexicon" "$CORPUS_DB" "$APP_DB" "$OUTPUT"
