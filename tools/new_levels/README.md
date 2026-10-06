# Appended levels 11–13

This directory contains reproducible test code and input fixtures, not generated results.

- `baseline_contract.json` pins the original ten level dictionaries, builder bytes, and both original aggregate route files to master `aeb95f10`
- `level11*`: cross-wing shortcuts, early dismount, non-overlapping keys, and death after the reunion key
- `level12*`: required cargo ferry, dry drop/reload, reversible-route mistakes, wall over-push, cargo reclaim, idle-partner and no-cargo counterexamples
- `level13*`: both independent objective orders, true timer expiration, wrong-side recovery, and independent escape-switch behavior

`*_routes.json` / `*_route.json` use waypoint controllers to author actual Input actions. `*replay*.json` and `level13_probes.json` contain immutable Input tapes. Neither mode relocates actors or injects puzzle channels. Expected frame counts, stars and mistake counters are asserted by replay; full completions also verify displayed, emitted and persisted results.

Run `python tools/run_checks.py --godot /path/to/godot` from the project root for the complete suite. For focused checks after resource import, run `python tools/run_new_level_checks.py --godot /path/to/godot --output-dir /path/to/results`. Results and temporary saves are kept outside these fixtures by default.

The old ten-level aggregate tapes stay unchanged. The default full suite runs them and the appended-level tapes separately. New levels are generated from `tools/enrichment/level_11.py`, `level_12.py`, and `level_13.py`; never edit `scripts/levels/levels.gd` by hand.
