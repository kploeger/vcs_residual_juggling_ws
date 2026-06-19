# Workspace Notes

This directory is mounted into Docker containers as /python_packages.

## Quick Context
- Any required dependencies or tools can be installed globally into the Docker container, but if we need them long term we'll want to add them to the Dockerfile and rebuild the container.

## Agent Hints
- For generic Python packages, warn if we introduce breaking changes. For application specific code (e.g. juggling), don't worry about backward compatibility and keep it clean instead.
- Compose code such that it can be easily reused in new projects.
- Deferred bugs go in `/python_packages/KNOWN_BUGS.md`. When we notice a bug but decide not to fix it right now (wrong scope, different branch, low priority, coincidentally harmless, etc.), add an entry with a file:line citation, a one-paragraph description, the proposed fix, and a "why deferred" note. Check this file opportunistically when touching related code.

## Juggler config (YAML + CLI shortcuts)

Hyperparameters live in a YAML file; a small set of CLI flags handle the
knobs you change every invocation. The flat-dict `config={...}` kwarg on
the juggler constructors is **dead** — pass `cfg=` (typed
`JugglerCfg`) only.

**Layering (low → high precedence):**

1. **Factory defaults** — `make_cascade_cfg(n_balls=5)` /
   `make_fountain_cfg` / `make_two_arm_fountain_cfg` /
   `make_single_throw_cfg` in
   `juggling_residual_learning/jugglers/config.py`. Every cascade and
   fountain factory's **cyclic** block defaults to
   `hold_on_pending=True` (freeze-and-wait under delayed feedback);
   the **individual** block does not.
2. **YAML cfg file(s)** — `--cfg PATH` (repeatable; later files override
   earlier). Loaded via `runners/cfg_io.py::apply_cfg_files` which
   deep-merges onto the factory cfg using
   `juggling_residual_learning/utils/config_utils.py::deep_update_dict`.
   Strict unknown-field rejection — typos raise `ConfigKeyError` with
   did-you-mean suggestions. The `individual:` / `cyclic:` blocks are
   replaced as-a-whole (not merged) because their contents are
   learner-type-specific. A YAML-supplied `cyclic:` block has
   `hold_on_pending: true` injected on each arm unless explicitly set
   (`_inject_cyclic_hold_default`) — so the cyclic-hold default sticks
   even when the YAML changes the learner type.
3. **CLI shortcuts** — small fixed set: `--learner-type`,
   `--individual-learner-type`, `--cyclic-learner-type`,
   `--hold-on-pending`, `--seed`, `--balls`, `--throws`, `--attempts`,
   `--runs`, `--n-individual-learners`, `--first-arm`, `--alternate`,
   `--ros`, `--no-render`, `--autoapprove`, `--no-plots`, `--tag`,
   `--tool-*`. Everything else is file-only.
4. **Tool overlay** — `--tool-*` flags via
   `runners/tool_args.py::apply_tool_overlay_to_cfg`.

**Canonical pipeline (used by every `runners/exp_*.py`):**

```python
cfg = build_juggler_cfg(
    args, make_cascade_cfg,
    factory_kwargs={"n_balls": args.balls},
    resolve_deadbeat=True,
)
juggler = CascadeJuggler(env_type=env_type, cfg=cfg, ...)
```

`runners/learner_args.py::build_juggler_cfg` composes the four layers and
returns an immutable `JugglerCfg`.

**File layout:** runners (`runners/exp_*.py`) are entry-point scripts —
they have no per-runner config files. Out of the box they default to
`NewtonCfg()` for both `individual` and `cyclic` blocks (with cyclic
getting `hold_on_pending=True`).

Config YAMLs are **experiment-specific** — they live alongside the
experiment that consumes them, under a `configs/` subdir:
- `experiments/method_sweep_5ball/configs/` — one file per learner
  variant for the 5-ball method sweep (newton, locally_linear, bobyqa,
  newton_smith_pd, …).
- `experiments/real_robot/existence_proof_5ball/configs/` —
  hardware-run tuned configs (e.g. `newton_best_known.yaml`).

Field names in the YAML match the `JugglerCfg` / `LearnerCfg` dataclass
fields exactly. The `individual:` / `cyclic:` blocks use the
`ArmedLearnerCfg.from_dict` shape — either `symmetric: {type: …, …}` or
`right: {type: …, …}` + `left: {type: …, …}`. The `type:` key inside
the learner cfg discriminates which `LearnerCfg` subclass (see
`LEARNER_REGISTRY` in `juggling_residual_learning/learners/_cfg_base.py`).

**Sweep harness:** `experiments/method_sweep_5ball/run_one.py` writes a
temporary YAML per sweep point and passes `--cfg <tmp>` to
`exp_31.main()`. No monkey-patches.


