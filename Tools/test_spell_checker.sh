#!/bin/bash
#
# Compile and run the spell checker tests against the generated database.
#
#   Tools/test_spell_checker.sh [corpus text file]
#
# Build the database first with Tools/build_dictionary_db.py. With a corpus
# text file (one sentence per line, words separated by spaces, such as
# khmer-text-data/oscar_kh_1.txt), it also reports how often real text gets
# flagged and how well synthetic misspellings are corrected.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DB="$PROJECT_DIR/Mini Khmer Dictionary/Resources/khmer_dict.sqlite3"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -f "$APP_DB" ]] || { echo "missing $APP_DB — run Tools/build_dictionary_db.py first" >&2; exit 1; }

swiftc -O \
    -module-name SpellCheckerTests \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -o "$BUILD_DIR/spell-checker-tests" \
    "$PROJECT_DIR/Mini Khmer Dictionary/Model/KhmerSpellChecker.swift" \
    "$PROJECT_DIR/Mini Khmer Dictionary/Model/KhmerWordPrediction.swift" \
    "$PROJECT_DIR/Tools/SpellCheckerTests/main.swift"

"$BUILD_DIR/spell-checker-tests" "$APP_DB" "$@"
