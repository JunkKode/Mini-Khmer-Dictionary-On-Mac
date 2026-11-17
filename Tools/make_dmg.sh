#!/bin/bash
#
# Package the app into a distributable .dmg.
#
#   Tools/make_dmg.sh                 # build Release, then package
#   Tools/make_dmg.sh path/to/App.app # package an app that is already built
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$PROJECT_DIR/build_dmg.sh" "$@"
