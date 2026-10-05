# Cooperative lift, portal and sightseeing levels

- L5: a keeper supplies A while the courier escorts cargo. Unload at B first or
  scout ahead to C first, then return. C brings the keeper upstairs; cargo at B
  frees both actors for the summit. Releasing A pauses the platform.
- L6: P1/P2 are fixed two-way hub/balcony pairs. Either branch may go first; each
  shared key needs simultaneous upper and lower participation. Latched keys let
  the pair revisit either branch for gems.
- L7: a short continuous dry promenade is the main route. Optional sightseeing
  uses A to send a visitor, who enables B for the partner. No hazards, boxes or
  required gates. Targets are 100 / 100 / 70 seconds, pending human tuning.

`replays.json` includes full-gem main/alternate/recovery fixtures, including
cargo blocked beneath a returning lift, normal clearance, reload and completion.
`scenario_replays.json` covers isolated mistakes and the optional-skip promenade.
The underlying safety implementation is `scripts/objects/moving_platform.gd`.

From the repository root:

```sh
python tools/gen_levels.py
python tools/enrichment/seven_middle/test_layouts.py
python tools/run_full_gem_routes.py --godot /path/to/godot --routes tools/enrichment/seven_middle/replays.json --output /tmp/middle-replays.json
python tools/run_full_gem_routes.py --godot /path/to/godot --scenario --routes tools/enrichment/seven_middle/scenario_replays.json --output /tmp/middle-scenarios.json
```

To re-author fixtures, `make_controllers.py` and `capture_and_verify.py` generate
controllers and local results. Generated reports and screenshots are not part
of this repository update. Non-completing scenarios are bounded at their recorded
checkpoint; their final idle tick after the controller checkpoint is excluded.
Raw tapes retain normal Input-only physics, with no actor or mechanism writes.
