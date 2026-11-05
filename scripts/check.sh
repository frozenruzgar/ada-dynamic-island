#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    echo "NOTE: Command Line Tools lacks XCTest; running the same shared SwiftPM check suite. Full Xcode CI uses swift test."
    swift run AdaChecks
else
    swift test
fi
