# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Context

- Non-ROS Python packages mounted into Docker at `/python_packages`
- All packages here are **auto-pip-installed** (`pip install -e .`) when the Docker container starts, so they are always importable inside the container
- Dependencies installed globally into the container are ephemeral; add long-term dependencies to the relevant `Dockerfile` and rebuild

## Tests

```bash
# trajectory_planning
cd /python_packages/trajectory_planning
pytest tests/

# juggling_residual_learning (pytest.ini sets testpaths = tests)
cd /python_packages/juggling_residual_learning
pytest

# juggle_planning, robot_control
pytest tests/   # from the respective package root
```

## Package Overview

### `trajectory_planning`
Motion planning library built on **CasADi** (symbolic math / NLP) and **Pinocchio** (kinematics/dynamics). Provides single-shooting and multiple-shooting trajectory optimizers, joint-space and Cartesian-space constraints, and cost functions. Used by `juggling_demos` ROS nodes for offline pre-computation of juggling trajectories.

### `juggle_planning`
Juggling-specific planning layer on top of `trajectory_planning`. Thin wrapper that adds juggling patterns and task-level constraints.

### `robot_control`
Pinocchio-based robot control algorithms (inverse kinematics, dynamics). Designed to be reused across projects independently of ROS.

### `juggling_rl`
Gym environment wrappers and training scripts for reinforcement learning on juggling tasks (`gym_envs.py`, `train.py`, `execute_last_policy.py`). Not a setuptools package. Trained checkpoints go in `checkpoints/`.

### `juggling_residual_learning`
Bayesian optimization + RL framework for residual policy learning on the real robot. Uses `botorch`/`gpytorch` for Bayesian optimization and `dm-control`/`mujoco` for simulation. Contains a `robot_description` submodule with MuJoCo builder scripts.

Two top-level directories for executable code:
- `runners/` — single-config CLI executors (`exp_30__learn_three_ball_cascade.py`, `exp_31__learn_five_ball_cascade.py`, …). Each runs *one* learning attempt with whatever flags it's given. Stable building blocks.
- `experiments/` — comparison studies that drive many runner invocations to produce paper figures/tables. One sub-dir per campaign; see `experiments/README.md`.

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


- For generic packages (`trajectory_planning`, `robot_control`), warn before introducing breaking changes. For application-specific code (juggling packages), prioritize clean code over backward compatibility.
- Compose code for reuse in new projects.
- **Never `pkill -f <pattern>`; use `juggling_residual_learning/scripts/killmatch.sh <pattern>`** (`-n` dry-runs). `pkill -f` matches every process whose full command line contains the pattern — including the shell running it and the `docker exec`/`ssh` wrapper that launched it — so killing a runner from a shell that names that runner kills the shell mid-command (exit 137, and anything queued after it silently never runs). `killmatch.sh` excludes self, ancestors and the matcher.
- **Benchmark with nothing else running.** The ROS stack's 1 kHz control loop has no headroom: launching it with `mj_render:=true`, running direct MuJoCo alongside the driver, or starting a test suite during a timed run all push it under real time, and the late sends read as ball drops — a convincing control failure that is pure artefact. Launch with `mj_render:=false` for measurements.
- **Siteswap success is measured over attempts, not on attempt 1.** Early throws are expected to be bad; compensating them is what the residual learning is for. Most patterns come good by attempt 3 and essentially all by 5, so report the per-attempt shape (`..SSS`) and the first successful attempt. Runs use `Seed: None`, so a single attempt-1 outcome is noise.
