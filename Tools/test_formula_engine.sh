#!/bin/bash
#
# Compile and run the formula engine tests without Xcode or a test target.
#
#   Tools/test_formula_engine.sh
#
# The engine (Model/Formula), the keypad logic (SimpleCalculator) and the
# Grid's sheets and selection (Model/Grid, except GridModel) and the Tools
# models (Khmer numbers, exchange rates, units, loans, lunar calendar) only import
# Foundation, so they build on their own alongside the test file.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="$PROJECT_DIR/Mini Khmer Dictionary/Model"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc \
    -module-name FormulaEngineTests \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -o "$BUILD_DIR/formula-tests" \
    "$SOURCES"/Formula/*.swift \
    "$SOURCES/Calculator/SimpleCalculator.swift" \
    "$SOURCES/Calculator/KhmerNumbers.swift" \
    "$SOURCES/Calculator/ExchangeRates.swift" \
    "$SOURCES/Calculator/CalculatorTools.swift" \
    "$PROJECT_DIR/Shared/KhmerLunarCalendar.swift" \
    "$PROJECT_DIR/Shared/KhmerHolidays.swift" \
    "$PROJECT_DIR/Shared/KhmerMonth.swift" \
    "$SOURCES/Grid/Spreadsheet.swift" \
    "$SOURCES/Grid/GridSelection.swift" \
    "$SOURCES/Grid/Workbook.swift" \
    "$SOURCES/Grid/GridFill.swift" \
    "$PROJECT_DIR/Tools/FormulaEngineTests/main.swift"

"$BUILD_DIR/formula-tests"
