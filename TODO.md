# TODO — residual_ws

Working list for agents in this workspace. Not Kai's personal todo list (that
is Todoist / the Obsidian daily note); this is for things discovered *in the
code and the data* that would otherwise be lost between sessions.

**Conventions**
- Every item states the EVIDENCE, not just the intent. An item nobody can
  re-verify is an opinion.
- Cite `file:line` or the run directory the number came from.
- Tick with `[x]` and leave the evidence in place — the record of why we did
  something is worth more than a short list.
- Add the date and who raised it.

---

## Open

### Hardware / calibration

- [ ] **Recalibrate OptiTrack.** (Kai, 2026-09-09)
  Of 26 coasting episodes in `data/real/real_robot/siteswap_sequence/std__cascade5_s0`,
  **17 had no marker within 0.40 m of an airborne ball** — the cameras lose it
  mid-flight. All 26 coasts ran to the full 50-frame ceiling
  (`max_frames_without_update`, 0.21 s at 240 Hz) and the track was then
  re-created with a new id, up to 7 times per ball per attempt. This is the
  root of the evaluation and closed-loop-catch failures; no software change
  substitutes for seeing the ball.

- [ ] **Test `dwell_ratio: 0.5` on the real robot.** (Kai, 2026-09-09)
  The chain stack silently runs **0.42**, set by
  `experiments/transitions/configs/best_chain_base.yaml` (both `pattern` and
  `siteswap` blocks). Kai: the most successful hardware juggling to date was
  at 0.5. `experiments/transitions/configs/chain_dwell_even.yaml` already sets
  0.50 and is NOT in the hardware stack — its own comment says 0.42 -> 0.50
  makes the two gaps equal (0.215 s each).

### Closed-loop catching

- [ ] **Enable `replan_at_fraction: vacant_mid` on the siteswap hardware stack.**
  Currently `None`, so the catch target is committed once at
  `planned_t = +0.467 s` (61 of 71 catches) plus ~0.089 s planning lead —
  **~0.55 s before the catch** — and never corrected, while the tracker goes
  blind for 0.21 s at a time. `replan_solve_budget` is already 0.06.
  Zero occurrences of "replan" in the entire 2026-09-08 hardware log.
  Prior art: `experiments/ros_uniform_{3,5}ball_closed`,
  `experiments/ros_siteswap_3ball_closed`.
  **Trap:** off MUST be expressed by omitting the key. `replan_at_fraction:
  null` emits the literal string "None" — `run_manifest` has no None guard.

- [ ] **Raise `max_adaptation` 0.05 -> ~0.15 once a pattern holds.**
  80% of adaptations (57 of 71) exceeded the 0.05 per-axis clamp; 29 exceeded
  the 2-axis corner 0.0707. Measured |dpos| med 0.065, **max 0.388 m** — the
  arm was told the ball was 39 cm away and moved 7 cm. Every one of those
  predictions was measurement-backed (`MAX_BALL_STATE_AGE_FOR_CATCH_S` = 30 ms).
  `experiments/ros_uniform_5ball_closed/manifest.yaml` already carries the
  measured curve: throws before a drop 0.10 -> 15, **0.15 -> 21**, 0.20 -> 13.
  Order matters: fix tracking first, or this just chases bad predictions faster.

- [ ] **The launcher ball is never caught closed-loop.** 9 of 9 launcher-fed
  candidates were `SKIP` (no usable touchdown prediction); all 71 adapted
  catches were thrown balls. It is the hardest catch in the pattern — 3.3 m
  drop, ~7 m/s arrival — and the only one always open-loop. Suspect the
  interaction of `_launcher_release_state_now` with the `tracked_ok` /
  `MAX_IN_FLIGHT_SPEED` branch in `jugglers/catch_pipeline.py`.

- [ ] **`two_stage` replan mode has never been run.** Only `vacant_mid` was
  ever enabled in any manifest or config; `two_stage` (vacant 0.3 + 0.6)
  exists in code and comments only. If a comparison is wanted it is an
  experiment, not a lookup.

### Safety

- [ ] **Pre-build every per-tempo NLP variant at load.**
  `_assert_safety_references_present()` (`jugglers/cascade_juggler.py:1102`)
  runs ONCE at construction and can only see keys that exist then. Per-tempo
  variants such as `cyclic_stop@0.500` / `@0.504` are created lazily when the
  chain first reaches a 0.50 segment (beat 26+, the 504), so they bypass the
  check entirely and the guard **fails open** — those stops executed
  unguarded on 2026-09-08. The chain is fully known at load time, so every
  tempo is knowable up front. Kai's invariant: every segment gets a fallback
  before anything executes. (Its own docstring records the same class of
  failure previously with `catch_and_stop@0.600`.)

### Instrumentation

- [ ] **Persist planner iteration counts, and archive the console log.**
  `nominal_solve_iterations`, `replan_iterations` and
  `nominal_solve_wall_time` are `None` in **every** saved throw. The ipopt
  iteration count exists only in the ROS console log, which is not part of the
  run artifact — the 2026-09-08 postmortem could only answer "did we hit
  `max_iter`?" because one log happened to survive in `~/.ros/log`.
  For the record from that log: 160 solves, **1 hit the `max_iter=20`
  ceiling**, 2 reached 19; but **54 of 160 exceeded the 25 ms reserved
  planning window** (max 52.2 ms) with zero late sends.

### Process

- [ ] **`docker_ws` should use `--init` (or tini) instead of `sleep infinity`.**
  Needs Kai — it is a function in `~/.zshrc`. pid 1 never reaps, so every
  killed roslaunch leaves unreaped children: `rwam_plan` reached **168 zombies
  of 170 processes** over 42 hours. Killing them makes it worse (the killed
  process becomes another zombie); only a real init or a container restart
  clears it. Fixes all five containers at once.

- [ ] **Do not use `--restart-partial` on a run worth keeping.**
  It deletes the previous attempts. On 2026-09-08 an 18-attempt real-robot
  cascade5 run (the `posterior` track-association arm) was destroyed this way;
  only the 8-attempt `pattern` run survives, so the two arms can no longer be
  compared. Archive the seed dir first.

- [ ] **Consider the velocity-direction association term on ball.**
  `optitrack-ball-tracker` on ball is `master`, which does not implement it at
  all; the work is on `origin/velocity-direction-association`. Application ids
  are assigned by pure Euclidean position (gate 0.30 m, switch penalty 0.20) —
  no heading term — and two balls crossing share a position but not a heading
  (measured: of 152 airborne samples with two balls within 0.15 m, 100% differ
  in heading by >90 deg). Implemented but NOT validated to help; the gate
  geometry A/B found no gap clearing 2 SE.

---

## Done

_(nothing yet)_
