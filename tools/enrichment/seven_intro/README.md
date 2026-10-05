# Cooperative introduction: levels 1 and 2

L1 is a short reciprocal rescue: Fire holds A for Water's lower passage, then
Water holds B until Fire crosses the upper arch. Both gates wait for occupants
before closing. L2 reuses one crate: a keeper admits it through A, it powers B
while the scout opens C, then moves to D. C is a permanent return path. Either
actor may be courier, and an overshoot can be pushed back using the teammate's
support. Targets are 40 s / 70 s, pending human tuning.

## Fixtures and use

- `replays.json`: primary, alternative-role/order and mistake-recovery Input tapes
- `controllers.json`: readable routes used to author those tapes
- `scenario_replay.json`: blocked-solo and wrong-order Input checks
- `scenario_controllers.json`: readable scenario authoring routes

From the repository root:

```sh
python tools/run_full_gem_routes.py --godot /path/to/godot --routes tools/enrichment/seven_intro/replays.json --output /tmp/intro-replays.json
python tools/run_full_gem_routes.py --godot /path/to/godot --scenario --routes tools/enrichment/seven_intro/scenario_replay.json --output /tmp/intro-scenarios.json
```

The runner creates isolated saves and generates its results at the requested
output path. Generated reports and screenshots are not checked in for this
release. Controllers use only Input actions; controlled unit fixtures elsewhere
are distinct from full-level gameplay routes. L2's short A barrier intentionally
blocks cargo while letting the departing keeper jump over it.
