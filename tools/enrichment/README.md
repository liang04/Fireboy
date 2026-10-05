# Level source and replay generations

`level_01.py` … `level_10.py` are the current generator sources. Generate the
runtime data with `python tools/gen_levels.py`; do not edit levels.gd by hand.

Current validation entry: `python tools/run_checks.py --godot /path/to/godot`.
It uses `prototypes/` for unchanged levels 3/4/8 and `seven_intro/`, `seven_middle/`,
`seven_final/` for the seven expanded levels. `seven_baseline_contract.json`
freezes the previous 4.7 release so retention and revision checks are explicit.

Older loose route, replay and probe JSON files in this directory describe the
prior enrichment layout. They remain as historical authoring evidence, and
are no longer loaded by the current aggregate suite for changed levels. Their
old successful results must not be presented as current-build verification.
