#!/usr/bin/env bash
# Renders the overlay on a virtual display (xvfb) while the mock plays the
# demo scenario, saving PNGs to test_output/shots/. Linux only; needs xvfb-run.
# Usage: tools/take_screenshots.sh "7:race_lobby.png" "15:race_running.png" ...
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$PWD/test_output/shots"
SCENARIO="${SCENARIO:-res://tools/scenarios/demo.json}"
mkdir -p "$OUT"
touch test_output/.gdignore  # keep Godot from importing logs/screenshots
PORT=$((20000 + RANDOM % 20000))
"$GODOT" --headless --path . --script res://tools/mock_streamerbot.gd -- --scenario="$SCENARIO" --port="$PORT" >"$OUT/mock.log" 2>&1 &
MOCK=$!
sleep 1
args=()
last=0
for spec in "$@"; do
  t="${spec%%:*}"
  args+=("--screenshot=$t:$OUT/${spec#*:}")
  last=$(python3 -c "print(max($last, $t))")
done
RUN=$(python3 -c "print($last + 2)")
timeout $((${RUN%.*} + 60)) xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy -- \
  --port="$PORT" --run-seconds="$RUN" --screenshot-bg="#303846" "${args[@]}" >"$OUT/app.log" 2>&1
rc=$?
kill "$MOCK" 2>/dev/null; wait "$MOCK" 2>/dev/null
grep -E "^\[screenshot\]" "$OUT/app.log"
exit $rc
