#!/bin/bash
#
# Compile and run the formula engine tests without Xcode or a test target.
#
#   Tools/test_formula_engine.sh
#
# The engine (Model/Formula) and the keypad logic (SimpleCalculator) only
# import Foundation, so they build on their own alongside the test file.

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
    "$PROJECT_DIR/Tools/FormulaEngineTests/main.swift"

"$BUILD_DIR/formula-tests"
