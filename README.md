# lucidin-chaos (odditorium-widget)

A free-for-viewers Twitch stream overlay built with **Godot 4.7.2**, driven by
**Streamer.bot** events. Viewers trigger silly on-screen shenanigans with chat
commands; channel point redeems are an optional extra. Nothing ever involves
bits, subs or donations.

> Work in progress: this is the stage-1 README (core + mock + tests).
> The full guide (config reference, art swapping, OBS/Streamer.bot hookup) comes in the docs stage.

## Quick start

1. Install Godot **4.7.2-stable** (standard build, not .NET).
2. Run the tests: `./run_tests.sh` (or `GODOT=/path/to/godot ./run_tests.sh`).
3. Try it without Streamer.bot: start the mock, then the overlay.
   ```sh
   godot --headless --path . --script res://tools/mock_streamerbot.gd -- --scenario=res://tools/scenarios/demo.json --loop
   godot --path .
   ```
4. End-to-end checks: `tools/run_integration.sh` (needs bash + python3).
