#!/usr/bin/env bash
# Runs the automated test suite headless. Usage: ./run_tests.sh [--filter=text]
# Set GODOT to your Godot 4.7.2 binary if it isn't on PATH as "godot".
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
# Build the global class cache (class_name) the first time / after changes.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$@"
