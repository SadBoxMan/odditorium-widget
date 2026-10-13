#!/usr/bin/env bash
# End-to-end check: runs the real overlay headless against the mock
# Streamer.bot server for each scenario and verifies the STATS it reports.
# Logs land in test_output/integration/. Needs bash + python3.
# Usage: tools/run_integration.sh   (GODOT=/path/to/godot to override)
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=test_output/integration
mkdir -p "$OUT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

failures=0

run_case() {
  local name="$1" scenario="$2" config="$3" password="$4" seconds="$5"
  local port=$((20000 + RANDOM % 20000))
  local pw_arg=()
  [[ -n "$password" ]] && pw_arg=(--password="$password")
  echo "=== $name (port $port, ${seconds}s)"
  # The mock keeps serving after its scenario so the overlay's final state is
  # "connected"; it is stopped once the overlay exits.
  "$GODOT" --headless --path . --script res://tools/mock_streamerbot.gd -- \
    --scenario="$scenario" --port="$port" "${pw_arg[@]}" \
    >"$OUT/$name.mock.log" 2>&1 &
  local mock_pid=$!
  sleep 1
  "$GODOT" --headless --path . -- --config="$config" --port="$port" --run-seconds="$seconds" \
    >"$OUT/$name.app.log" 2>&1
  local app_rc=$?
  kill "$mock_pid" 2>/dev/null
  wait "$mock_pid" 2>/dev/null
  echo "app exit=$app_rc"
  if [[ $app_rc -ne 0 ]]; then
    echo "FAIL: overlay exited with $app_rc"; failures=$((failures + 1))
  fi
  if ! python3 tools/check_integration.py "$OUT/$name.app.log" "$OUT/$name.mock.log" "tests/integration/expect_$name.json" >"$OUT/$name.check.log"; then
    failures=$((failures + 1))
  fi
  grep -E "^(OK|FAIL)" "$OUT/$name.check.log"
}

run_case edge_cases res://tools/scenarios/edge_cases.json res://tests/integration/integration_config.json "" 30
run_case auth res://tools/scenarios/auth.json res://tests/integration/integration_auth_config.json mock-password 12

if [[ $failures -gt 0 ]]; then
  echo "INTEGRATION: $failures failure(s); see $OUT/"
  exit 1
fi
echo "INTEGRATION: all passed"
