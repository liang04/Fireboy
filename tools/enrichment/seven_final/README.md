# Final cross-repair and cargo relay levels

L9's elemental repairs power the partner's lift. The roof retains permanent
support and offers reversible A/B access; either roof order is possible and each
landing has a way to reverse a mistaken choice. The target is 90 seconds.

In L10 both actors prepare high loading key K before delivery. H releases cargo
to the dry staging apron; J releases it into the well. Both are rechargeable and
retain six seconds after release. Either keep roles or exchange them mid-route.
J sits off the direct H path, and K's separate upper pads are inaccessible to
cargo. The well receiver covers the entire floor; R1 is an unconditional
player-only escape. The target is 70 seconds, pending human tuning.

## Fixtures

- `replay_*.json` and `replays.json`: primary, alternative and recovery Input tapes
- `route_*.json`: readable authoring routes
- `probes_replay.json`: raw-input cross-repair/cargo counterexamples
- `probes.json`: readable authoring probes
- `solo_bypass_regression.json`: former solo cargo solution and sequential K-pad
  visits must remain blocked without the second actor

Run the full suite with `python tools/run_checks.py --godot /path/to/godot`, or
use `tools/run_enrichment_checks.py` with `--output-dir` to choose where generated
results are saved. No generated report or screenshot is included in this update.
The geometry assertions supplement real Input tapes rather than replace them.
Existing artificial low ceilings crossing lift shafts are not generally safe;
shipped lift interiors are clear, with actual edge recovery covered separately.
