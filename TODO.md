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

- [ ] **Recalibrate OptiTrack.** DOWNGRADED from "root cause" 2026-09-09 —
  see the correction below; still worth doing, no longer the top item.
  Testing each of the 26 coasts by whether the raw marker COUNT actually
  dropped: **19 markers still present (association failure), 7 genuinely lost
  (mocap)**. My earlier "17 of 26 had no marker within 0.40 m" measured
  distance from a *diverging* coasting estimate, so it partly measured the
  drift it was trying to explain. All 26 coasts still ran to the full 50-frame
  ceiling (0.21 s at 240 Hz).

- [ ] **APPLICATION UPDATES ARE STAMPED AT PUBLISH TIME, NOT AT THE INSTANT
  THEY DESCRIBE.** (Kai, 2026-09-09 — his diagnosis, confirmed in code.)
  `ball_tracker.py:563` sets `header.stamp = rospy.Time.now()` when the buffer
  is flushed. The content was computed earlier — a pattern query in
  `_update_all_ball_tracks`, or a scheduled callback such as
  `handle_ball_track_update_catch` firing at `t_catch` — so every bit of
  scheduler jitter, GIL wait and queueing between compute and publish is
  absorbed silently into the stamp. The tracker then places the track where
  the ball WAS while believing it is current.

  The tracker already has the machinery and cannot use it:
  `multi_ball_tracker_impl.hpp:1174` time-aligns for MATCHING, but only
  `if (update.timestamp > predictedKalman.getLastTimestamp())` — i.e. only
  when the update is NEWER. A delayed update is older, so no alignment
  happens and a stale expected position is compared against a current track,
  inflating the distance by |v|·dt (3 m/s x 20 ms = 6 cm, x 50 ms = 15 cm)
  against a 0.30 m gate. On a state reset (~line 1610) the position is
  written verbatim with `setLastTimestamp(update.timestamp)` and never
  propagated forward.

  FIX: stamp with the time the content describes, or propagate the content to
  publish time. Note `ApplicationUpdate` has NO per-update timestamp — only
  the array header — so a batch computed at different instants shares one
  stamp. Fixing this properly means adding a per-update stamp to the message.

- [ ] **An application update resets `framesSinceUpdate` to 0 with no
  measurement behind it.** `multi_ball_tracker_impl.hpp:1645-1647` sets
  `framesSinceUpdate = 0` and `lastUpdateTime = update.timestamp`
  unconditionally for any matched update, including match-only updates that
  perform no state reset. So our own expected-state publishing makes a
  coasting track look freshly measured. This defeats
  `MAX_BALL_STATE_AGE_FOR_CATCH_S` (the 30 ms catch gate) and means every
  coasting/staleness number measured from `frames_since_update` — including
  the ones in this file — is a LOWER BOUND.

- [ ] **Stop publishing an in-air expected state for a ball that is on the
  floor.** (Kai, 2026-09-09) `env_glue.py:959` already skips `ball.dropped`,
  but `dropped` only becomes true once the floor detector fires. A badly
  thrown ball needs ~0.6-1.0 s to reach the floor, the detector needs its
  confirmations, and a ball landing OUTSIDE `drop_detection_box` is never
  marked dropped at all. For that whole window we keep asserting an in-air
  position, which resets tracks to somewhere the ball is not. Gate on the
  ball's own tracked height as well as on the detector.

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
  CORRECTED 2026-09-09: my earlier "80% of adaptations were clamped" was true
  per-AXIS but overstated the effect, and read as though the clamp were
  crippling closed-loop catching. Measured on the norm, per throw (n=70
  adapted throws with a non-zero request):

      requested |dpos|   p10 0.041  med 0.065  p90 0.134  max 0.388 m
      applied   |dpos|   p10 0.041  med 0.054  p90 0.071  max 0.071 m
      retained fraction  p10 0.458  med 0.863  p90 1.000
      68 of 70 throws moved the hand >= 0.02 m; 28 of 70 retained >=90%

  So the clamp is NOT behaving like gain=0 -- the median throw keeps 86% of
  its correction and moves the hand 5.4 cm, against a 3.75 cm ball radius and
  a 7 cm cup radius. The adapted condition is behaviourally distinct from an
  unadapted one on essentially every throw.

  WHERE IT DOES BITE IS THE TAIL: 8 of 70 throws retained under half, and the
  worst residual is 0.317 m. Since one bad catch ends an attempt, the tail is
  what actually costs completions -- which is the argument for raising the
  clamp, rather than the average being crippled. Every one of those
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

- [ ] **`expected_states` is not recorded** (`None` in every attempt), so the
  publish-vs-describe delay above cannot be measured from saved data at all —
  only read off the code. Record the expected states we publish, with both
  the time they describe and the time they were published.

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

### Planning

- **A capped solve returns an INFEASIBLE trajectory, not a rough one.**
  (2026-09-10, agent) Everywhere this codebase reasons about
  `ipopt.max_iter` treats hitting the cap as "good enough, just not
  polished". It is not. Measured offline, 3-ball cascade
  `catch_and_throw`, 25 solves per correction size, worst constraint
  violation of the RETURNED solution (`g` against its own `lbg`/`ubg`,
  not IPOPT's self-report):

    | \|dx_catch\| | converged | hit the cap |
    |---|---|---|
    | 0.02 m | 1.1e-07 | 1.05e-05 |
    | 0.06 m | 5.9e-08 | 4.51e-05 |
    | 0.12 m | 5.1e-08 | **8.17e+00** |

  Converged solves are feasible to eight decimals; a capped one at a large
  correction is out by 8.17 (cone rows carry a x100 preconditioning factor,
  so ~0.08 raw). This is the mechanism behind the run-level correlation
  already on record — a capped solve preceded a drop within 4 throws
  65-71% of the time against 25-32% for a converged one — and behind
  `max_iter` 20 -> 10 taking cascade5 from 8/8 attempts to 2/8.
  Recorded at `juggling_residual_learning/jugglers/config.py`
  `_online_solver_options()`. Consequence: buy solve time with better warm
  starts or cheaper iterations, never by capping sooner; and never splice a
  capped solve into a moving arm.

- **`ipopt.acceptable_dual_inf_tol` is the sole binding acceptable
  criterion — awaiting Kai's decision.** (2026-09-10, agent) Loosening
  `acceptable_constr_viol_tol` (1e-5 -> 1e-4, 1e-3) or
  `acceptable_compl_inf_tol` (1e-2 -> 1e-1) changed nothing at all;
  `acceptable_dual_inf_tol` 1e-2 -> 1e-1 cut capping from 3/25 to 1/25 at
  |dx_catch| 0.06 with the max constraint violation bit-identical, because
  it relaxes OPTIMALITY rather than feasibility. Deliberately NOT in the
  tree: it changes the optimiser's path and so can move recorded numbers.
  `mu_oracle` loqo/probing are catastrophic (25/25 capped) — do not retry.

- **AOT codegen is opt-in and unused by default.** (2026-09-10, agent)
  `TP_NLP_AOT=1` compiles the generated CasADi C once per NLP into a
  hash-keyed object cache (`trajectory_planning/nlp.py`,
  `_aot_compiled_solver`), making function evaluation ~10x cheaper: full
  solve p50 7.16 -> 3.83 ms, replan 5.60 -> 3.35 ms, iteration counts
  unchanged. First cascade5 run pays ~10 min of compiling at -O1, every run
  after that nothing (warm build 7.5 s against ~6 s interpreted). Worth
  turning on for hardware runs if someone confirms the cache directory
  survives between them.

---

### 2026-09-11 — AOT compile, plant DR, second robot_description checkout

- **AOT cold compile is minutes, not seconds, and is now parallel.** The
  3->5 chain builds 90 NLPs per solver phase that hash onto ~43 distinct C
  sources of ~5 MB each; gcc -O1 takes ~40 s per object, so the first run
  after `c64b157` (AOT default) sat 478 s in build with 10 NLPs done and was
  killed by its own 480 s timeout (`_probe/gt_` run.log, 2026-09-11). Fixed by
  `aot_compile='deferred'` + `aot_finish_deferred()` (trajectory_planning
  0021dfb, juggling 30db96b): a warm build now logs
  `AOT: 90 cache hit(s), 0 compiled, 0 failed in 1.2 s (20 parallel jobs)`.
  Cache is `/retain/tp_nlp_aot` (43 objects, 83 MB). STILL OPEN: a cold
  cache after any NLP-structure change (cone knots, constraint tables) costs
  one parallel pass of ~2-3 min in the first run that sees it -- a sweep over
  constraint configs pays it once per point. Consider pre-warming in the
  sweep harness, or `-O0` for exploratory sweeps (5.7 s/object, 2.8x eval).
- **Planning lead can come down after AOT.** `_probe/gt_default3` (3/3,
  n=270 solves): planning p50 11.2 ms, p90 17.8, max 28.1 -- vs max 58 ms
  measured before AOT, which is what set `planning_lead: 0.090`. 0.060 would
  keep a 32 ms margin over the observed max; re-derive from the queue9 runs
  (held2, five048, send_advance_005) before changing it.
- **Two checkouts of `robot_description` in this workspace.**
  `python_packages/juggling_residual_learning/robot_description` and
  `catkin_ws/src/juggling_wam/juggling_wam_description/robot_description`
  are separate submodule checkouts of the same remote; the ROS renderer
  imports the catkin one, the planner-side builder the other. Today's
  DynamicsPerturbation landed in the python_packages copy and the ROS
  renderer failed with ImportError until the catkin copy was pulled. Both
  are at `9c47011` now. `juggling_wam` master had also been pointing the
  submodule at the `ball-dynamics-overrides` branch (e11e508) rather than
  master; merged into master today (9c47011). Keep them in lockstep, or add
  a check that both pointers agree.
- **Plant DR pipeline exists, results pending.** `utils/plant_randomisation.py`
  (seeded draw -> roslaunch line -> `plant_draw.json`). queue9's
  `plant_dr_mass_tilt` (tool mass+tilt only, hand-typed launch args) and
  queue10's `plant_dr_full` (all four knobs via the helper, seed 0) are the
  first runs; compare against `bisect_default_confirm` 7/8. Ranges
  (12% / 2 deg / 10% / 30%) are assumptions, not measurements.
- **`ros_message_send_advance`: 10 ms works, 5 ms does not.** 10 ms
  (`_probe/bisect_send_advance_010`, AOT on): **8/8**, zero late sends,
  smallest send margin 5.3 ms, planning p50 8.9 / max 28.9 ms (n=720). One
  session of 8; the 20 ms baseline is 7/8. Worth making the default in
  `ros_catch_replan.yaml` once a second session agrees -- it buys 10 ms of
  replan horizon per throw.
- **`ros_message_send_advance` 5 ms is not viable.**
  `_probe/bisect_send_advance_005` (AOT on, chain 3->5): 2/5 attempts, then
  the run ABORTED in attempt 6 with `SendDeadlineMissed` (a trajectory
  reached the wire 0.37 ms past its own start); smallest send margins seen
  0.22 / 0.62 / 0.74 ms, 2 late-send warnings. Planning itself was fine
  (p50 9.9, max 27.9 ms) -- the 5 ms is eaten by callback jitter (~2 ms,
  "callback fired +2.12ms vs target" is routine). Untested middle: 10 ms.
- **Held 0s/2s A/B result 2026-09-11 15:00: velocity constraint + READY
  parking = 7/8** (`_probe/bisect_held_fix_stopvel_ready`: only failure at
  throws 76-85 in the 5-ball tail of attempt 4; px throws -0.2 -> 0 by
  attempt 3, no wild variance). Same constraint + park-at-next-catch: 3/8.
  Held mode is therefore fixed by: from-rest slot (e6db696) +
  catch_hand_velocity on catch_and_stop (juggle_planning b42c600, overlay
  `_held_stop_catch_vel_ready.yaml`) + ready parking (the default).
  DECISION FOR KAI: make catch_hand_velocity a catch_and_stop default in
  config.py (it is only an overlay today); `next_catch` parking stays
  available but should not be the default.
- **Held 0s/2s, status 2026-09-11 15:00.** (a) `catch_hand_velocity`
  (juggle_planning) works: cup moving -0.2..-0.5 m/s at every held-2 catch,
  no 18/21/24 bounce in 8 attempts (`bisect_held_fix_stopvel`). (b) That run
  was still 3/8: with park-at-NEXT-catch the 5 thrown right after a rest
  (`i4_px_o5`) leaves with a random +-0.4..0.5 m/s z error (5/8 attempts),
  not seen with 'ready' parking (7/8). A/B queued: constraint + ready.
  (c) NEW, general: the min-speed candidate gate rejected balls at their
  APEX (z~1.62, |v|<0.05) 1-4 times per run -> nominal catch -> rim; fixed
  (APEX_HEIGHT_ABOVE_CATCH). (d) The AOT compile OOM-killed the desktop at
  13:59 (49 MB C x 20 jobs); memory guards + windowed constraint are in.
  (e) Open-loop re-use of a previous plan is now blended from the arm's
  state (a 0.116 rad/s mismatch crashed a run).
- **Held-2 bounce, status 2026-09-11 14:00.** `hold_rest_pose: catch`
  (`_probe/bisect_held_fix_park_catch`) 4/8, cup still +0.6..1.0 m/s up at
  touchdown -- parking alone does not change the stop trajectory's shape.
  Added `catch_hand_velocity` to the stop NLP (juggle_planning): cup z
  velocity at touchdown = 10 % of the ball's (~-0.45 m/s). Runs queued:
  `held_fix_park_next` (park at the NEXT nominal catch, Kai's ask) and
  `held_fix_stopvel` (that + the velocity constraint). Session variance is
  large: identical held configs went 7/8 and 3/8 an hour apart.
- **Held-2 catches bounce the ball out: the cup RISES into the ball.** In
  every attempt of `_probe/bisect_held_dt050`, the hand velocity at the
  `catch_and_stop` catch instant is (+0.45, ., +0.7..+1.2) m/s, against
  (+0.2, ., -0.2..-0.6) for a normal `catch_and_throw` catch: closing speed
  ~5.2 vs ~3.9 m/s. Attempt 4 throw 19: the incoming 4 reached the left cup
  at t-0.26 s and left it again at once (+x, toward the centre, up 15 cm,
  floor at (0.75, 0.13)); the track was measurement-backed to 5 mm the whole
  way, so this is a real ball, and the "throw 21 evaluation failed" drops
  (3/8 at 0.05, 2/8 at 0.03, 1/8 with the slot fix) are this. Cause: the
  stop NLP constrains only the joint POSITION at the catch and then
  decelerates to `hold_rest_pose = ready`, which is ~7 cm higher and
  forward of the catch, so the optimizer drives the cup up through the
  catch. `catch_and_throw` has `min_tool_normal_acc` and a dip before the
  throw; `build_catch_and_stop_nlp` does not accept that constraint at all
  (juggle_planning planner.py `possible_constraints`). Tests queued:
  `hold_rest_pose: catch` (`_held_park_catch.yaml`, with the slot fix). If
  that is not enough, add `min_tool_normal_acc` support to the stop NLP or a
  touchdown-velocity constraint.
- **Held 0s/2s after the fix: 7/8 at the stack's own 0.02 clamp**
  (`_probe/bisect_held_fix_dt020`; from-rest slot 0.500 s confirmed). The
  one failure is attempt 8 at throws 18/24, the 423 from-rest oddity below.
- **Held 0s/2s: the REAL bug was the from-rest throw's slot (fixed).** With
  the clamp at 0.03 (`_probe/bisect_held_dt030`, 0/8) the throw-34 failure
  disappeared (the `px` learner converges by attempt 3) and the chain died at
  throw 70 in 5/8: throws out of a held 2 in 552@0.50 ran 0.600 s (padded to
  the base cycle), the right arm slipped 100 ms per hold, the incoming 5 was
  rejected by `max_catch_prediction_dt` (0.10) as "right place, wrong beat",
  nominal catch, miss. Fixed in siteswap_juggler `_from_rest_slot_duration`
  (2026-09-11). Also seen: throws 18/21 (`i2_p2_o4`, from rest in 423)
  failed in attempts 7-8 with the learner offsets unchanged from the passing
  attempts 2-6 -- ball landed 23 cm forward; unexplained, 2/8.
- **Held 0s/2s fail on EARLY balls because the catch-time clamp is 0.02 s.**
  `_probe/gt_held2` attempt 2, throw 34 (`ssbank_right_i5_p5_o4_t50`):
  predicted landing -0.0755 s, `catch_applied_dt` -0.020 (the clamp), hand
  dipped 56 ms after the ball, ball hit the rim (GT x 0.5 -> 0.1 m, floor at
  y=-1.05). The no-hold run's same throw: -0.052 s predicted, 32 ms residual,
  caught. The 0.02 was set (best_chain_catch_clamp.yaml) to stop LATE
  adaptations eating the carry on 645's beat 70; the late side has since got
  its own `max_time_adaptation_late: 0.005`, so the early side is clamped for
  a reason that no longer applies. Test queued: `_held_dt080.yaml`
  (`max_time_adaptation: 0.08`, held 0s/2s, 8 attempts) + a 4-attempt held
  control. Root cause upstream of that: 5s thrown right after a rest beat
  (`i4_px_o5`) leave 0.25 m/s slow in z on early attempts in BOTH modes.
- **Do not render or run test suites during a timed ROS run.** gt_held2
  attempt 1 dropped at throw 10 after a 0.147 rad j4 tracking spike at the
  throw-7 release that coincides with an unniced x264 render on all cores;
  the overnight held run never failed before throw 18. Renders now go
  through `nice -n 19 taskset -c 20-23`; queue9 puts the full suites in the
  gap between runs.

### 2026-09-11 — the "twitch" around the 0 of the 504: FIXED (post-takeoff constraints on a phantom ball)

**Root cause.** The catch_and_throw after a 0 starts from rest, but
`post_takeoff_cone` (k=[2]) and `post_takeoff_min_separation` (k=[2..6],
0.02 m) assume k=0 is a release and predict the "ball" ballistically from the
START state (`juggle_planning/constraints/cone_constraints.py`). After a 0 that
ball is a phantom sitting in the cup that free-falls; the cone's sign
inequality and the separation then force the cup UNDER it. Measured on throw
32 (`ssbank_right_i4_px_o5_t50`) in `_probe/gt_held_fix/run/attempts/002` and
`_probe/gt_default3/run/attempts/001`: hand z 0.54 -> 0.47 -> 0.55 m in the
first 120 ms, j4 dq_des -5 -> +4 rad/s, ddq_des +-240 -- identical in the HELD
(rest_no_ball) and TOSSED (toss_no_ball) runs, so it is not a hold artefact.
Side effect: the catch-adaptation replans for that throw tripped the safety
guard (ddq 534 / 871 > 450, `replan_rejected_reason: guard_fallback`) in both
runs, so the post-0 throw -- the one Kai found "too early to compensate for"
-- also ran WITHOUT catch adaptation.

**Fix (Kai: "get rid of those constraints for starting from 0s, both held and
thrown").** New reparameterizable `axial_slack` on both constraints
(juggle_planning 6fb7279) + `POST_TAKEOFF_INERT` context override keyed
`prev_throw=0` on both arms' catch_and_throw and catch_and_stop tables
(juggling c1fe6ef). Per-solve parameter vector, no NLP rebuild; the AOT cache
misses once because the parameter vector grew (every c&t / c&stop NLP
recompiles on the next launch, deferred + parallel, memory-guarded).

**Verified for the tossed 0** on `_probe/bisect_fix_default` (full chain,
7/8, deepest throw 89, planning max 33.7 ms): throw 32's first 150 ms now
peak at |ddq_des| 70-72 rad/s^2 (was 220), the dip and the j4 reversal are
gone (plot `scratchpad/twitch_fix.png`), and the catch-adaptation replan of
that throw is ACCEPTED in attempts 1 and 2 (was guard_fallback in both old
runs). **Verified for the held 0 too** (`_probe/bisect_fix504_held`, chain
3x12,423x4,44,504*: 8/8; thrown-0 twin `bisect_fix504_thrown` 7/8, attempt
1 dropped): throw 32 peak |ddq_des| 61-64 (held) / 73 (thrown) against 242
before, no dip, no j4 reversal, replans accepted in every attempt
(`scratchpad/twitch_504.png`). Closed.

### 2026-09-11 — app-id association: posterior source wins, velocity gating is neutral

`experiments/app_id_association/run.py`, open-loop chain, 8 attempts, scored
by `association_truth` (wrong-ball % mean, lower is better):
pattern_vel0 6.8 / pattern_vel010 9.5 / pattern_vel010_pen0 9.3 vs
posterior_vel0 1.27 / posterior_vel010 1.34 / posterior_vel010_pen0 1.46 /
position_only 1.53 / vel_dir_010 1.33. Switch counts 160-206 (pattern) vs
20-32 (posterior). Conclusion: seed the association from the tracker
POSTERIOR, not the pattern's desired state (the juggler already defaults to
it); the four {switch penalty 0.20/0} x {velocity direction 0.10/0} cells
(1.27 / 1.53 / 1.34 / 1.46) are within a quarter point. Kai's decision
(2026-09-11): ship velocity direction 0.10 with the switch penalty OFF --
the heading term is the principled discriminator, the penalty is memory.
Done: optitrack-ball-tracker 777e1aa. Runs launched BEFORE that commit's
sim relaunch (queue22's 504 probes and `bisect_fix_default`) ran on penalty
0.20; `long_reps` onward relaunch and pick up the new default.

### 2026-09-11 — the catch AFTER A 0: raised park is now the chain DEFAULT; box still to test

Scope (Kai, 17:11): the catch out of a 0 only. `siteswap.hold_rest_z_offset`
lifts the 0-beat rests (not a held 2); after the held-0s 504 video with 3 cm
(`_probe/gt_held504_restup`: 3/3, 88 throws each, joint plot clean) Kai:
"Video looks good. Let's keep it like that." -> 0.03 in
`configs/settings_20260909.yaml` (the chain stack), overlay removed. Default
parking twin `_probe/gt_held504_default` recorded for the side-by-side.
Post-0 touchdown-velocity BOX (`_post0_catch_dz_box.yaml`, `only_after_zero`;
cup at least 0.5 m/s down, at most half the ball's z speed): RESULT 19:02,
`_probe/bisect_post0_box` 7/8 (attempt 1 drop, throw 89, planning max 45.3
vs 25-35) against the matched `bisect_transient_kd0` 8/8. The window never
binds: throw 32 arrives at -1.40..-1.44 m/s both ways, climb 8-9 cm both,
peak |ddq| 67-72 both. Inert here -> stays OFF; keep the overlay as the
tested implementation. With the raised park the post-0 climb is 8-9 cm
(was 10-11 cm; normal follow-through 15-16 cm).
Joint 4 sits at 1.77-1.78 of its 1.8 rad limit on every normal
follow-through, so a lower GLOBAL q_max would clip every throw; a post-0 cap
is possible as a prev_throw=0 override if the climb still matters.

### DONE 2026-09-11 — transient learners' unintended D-term: ablated (no difference), kd now 0 by default everywhere (juggling 9c942e9)

**The bug.** `NewtonCfg.delay_strategy` defaults to "smith_pd"
(learners/newton_raphson.py:18) and an unset kd resolves to 0.2 there (:184).
hold_on_pending is injected only on the cyclic block, so the individual /
transient learners run smith_pd with a LIVE D-term (the Smith part is inert:
nothing is ever pending for a transient): every transient step adds
-0.2 * J_inv @ (ema_err_n - ema_err_{n-1}) once two tells are in. Reported by
isrr_rerun; confirmed on THIS chain (`_probe/bisect_fix_default/run/config.json`
individual blocks: hold_on_pending false, smith_pd, kd null, lines 965-1011)
and in the recorded ISRR / real-robot existence-proof configs. Kai's intent:
plain Newton for transients (no D, no Smith). The ISRR paper keeps the
recorded runs as they are.

**The ablation (Kai: "We need to ablate learning over turning this off").**
Overlay `_transient_kd0.yaml` (individual block kd 0.0, nothing else) vs the
chain as is (kd 0.2). Queued FIRST (queue33, Kai 17:39: "the next important thing"):
`_probe/bisect_transient_kd0` vs `_probe/bisect_transient_kd02_baseline`
(same code, same session, back to back; raised park is default in both),
plus the held chain with kd 0 and its kd 0.2 baseline.
**Default chain result (18:12):** kd 0 `✓✓✓✓✓✓✓✓` (throw 89, planning
max 34.7) vs kd 0.2 `✓✓✓✓✓✓✓✓` (throw 89, 24.7). Transient-beat mean |dv|
per attempt, kd0 / kd0.2: 0.119/0.126, 0.046/0.052, 0.025/0.040,
0.019/0.023, then 0.02-0.04 both; cyclic beats identical (0.03-0.04). The
D-term does nothing measurable on the transients. Held chain kd 0: 8/8
(throw 89, planning max 26.8), transient 0.141 -> 0.023 by attempt 4;
held kd 0.2 baseline running at the time of writing (report when in).
Kai: "make sure the k_d term is zero by default for everything we may ever
do in the future" -> newton_raphson.py defaults kd to 0 in every strategy;
explicit kd still honoured (test_newton_kd_default_off.py).
Config wart fixed (juggling 9d0b22b): the dead `individual: pd` block is
gone from `settings_20260909.yaml`; a transient learner never has a pending
ask (it is not queried before its previous candidate reports back), so
Smith cannot fire for it whatever the strategy says. Resolved stack
unchanged in effect.
Read out: success rate and per-attempt shape, first successful attempt,
transient-beat velocity errors over attempts (the D-term acts on the
transients only), and whether the cyclic beats inherit better inits. Every
run today shares kd 0.2, so today's A/Bs stay internally consistent; do not
change the default until the ablation is in. If kd 0 wins, the fix is either
hold_on_pending on the individual block too or kd -> 0 whenever nothing can
be pending; then re-baseline.
### 2026-09-11 — first full-DR pair produced nothing: unquoted mj_plant_args (fixed), requeued

`_probe/bisect_plant_dr_full/run.log`: "Failed to initialize time" after
25 min -- the DR sim never launched because the plant args were several
unquoted tokens on the shell line and roslaunch bailed with "no such
option: --armature-scale-left" (/tmp/launch_dr_full.log). Fixed in
plant_randomisation.py (shlex.quote) with a shell-split test; queue10.sh now
aborts on an unhealthy launch instead of running the juggler against a dead
sim. DR pair requeued as queue32 after the post-0 experiments (queue30).
The nominal-plant "back" launch in that queue is healthy, so nothing else
was affected. The veto probe ran: 0 vetoes.

### 2026-09-11 — FULL plant DR seed 0 breaks the chain: 0/8 (link masses + armature are the new part)

`_probe/bisect_plant_dr_full` (launch fixed, plant reports the draw: link
masses x0.95..1.10, armature x0.88..1.24 per joint, plus tool mass/tilt):
`✗✗✗✗✗✗✗✗`, deepest throw 51, planning max 34.3. Drops cluster in two
places: the 504 block (attempts 4, 5, 8 end at throws 35-38 on a
`catch_and_stop` with `catch_fallback_reason=no_usable_prediction`) and the
4x12@0.50 block (attempts 6, 7 end at throws 44-49; one catch miss of
0.41 m at throw 45). The learners are NOT the problem: transient and cyclic
velocity errors reach 0.02-0.05 m/s by attempt 4 as on the nominal plant.
The overnight 2026-09-09 DR (tool mass/tilt only) was 7/8, so the armature
/ link-mass mismatch is what breaks it -- exactly the model error the
residual is supposed to absorb, so this is the important negative result of
the day. Same-code nominal reference: `bisect_transient_kd0` 8/8.
Axis bisect at seed 0 (queue34, 2026-09-11 evening), 8 attempts each:
armature only 6/8 `✗✗✓✓✓✓✓✓` (drops at 50, 69), link masses only 7/8
`✗✓✓✓✓✓✓✓` (50), tool mass+tilt only 7/8 `✗✓✓✓✓✓✓✓`, full draw at HALF
range 6/8 `✓✓✗✓✓✓✗✓` (36, 48) -- against the full draw's 0/8 (35-38,
44-49). Every axis alone is close to nominal (8/8); the combination at
half range still passes; the full-range combination fails every attempt in
the same two places. So it is the combined magnitude, not one axis. Next:
locate the boundary (full draw at 0.75 range; a second seed at full range)
and look at what the 504 stops (35-38) do under the combined mismatch --
`catch_fallback_reason=no_usable_prediction` there means the ball the stop
was waiting for was never predicted, i.e. the preceding throw was already
off. Not run tonight: the box is handed to TLL_planner's tracker build.

### 2026-09-11 evening — ROBOT READINESS (three reviews; reports in .claude/reviews/robot-readiness-*.md and full-2026-09-11-evening.md)

Kai: "we will try held 2s on the real robot ... anything that could still go
wrong on the real robot?" Status per item:

DONE tonight
- Held-2 touchdown-velocity constraint + 10 ms send advance -> chain stack
  defaults (juggling, 2026-09-11 20:28, after the DR bisect finished;
  overlays removed). NOTE for the queue scripts: `_held_stop_catch_vel_ready.yaml`
  no longer exists -- held runs need only `--hold-0s --hold-2s` now.
- Hold/rest poses pre-warmed at construction (juggling 461e887): an
  unreachable lifted pose is an init error, not a mid-cycle exception.
- Tracker master fast-forwarded to 777e1aa (2026-09-11 19:55, agreed with
  TLL_planner: their rebased commits are already in it; their two new ones
  -- a yaml comment fix and velocity-term tests -- follow after a build).
  A robot PC on master now has measurement_backed, the velocity term and
  penalty 0; preflight.sh checks the live message anyway.

KAI'S CALL
- Joint-4 envelope from the OPENING segment (`config.py:2119-2126`): the
  cascade5 chain keeps q_max 1.8 for its 5-ball tail although the 5-ball
  factory bumps it to 1.9; joint 4 sits at 1.77-1.78 on every follow-through
  (measured today). Chain runs 7/8-8/8 as is. Change = size from the peak
  ball count. Not touched (finalisation rule).
- `JRL_ROS_STRICT`: default kills the whole run on one missed send deadline
  (sim policy, Kai 2026-08-28); the code says =0 ("abort the attempt, keep
  the run") is what a supervised real-robot session wants. Nothing under
  experiments/real_robot sets it. Decide per session; if =0, put it in
  preflight/run_next, not in a shell history.
- Floor-drop check (`drop_detection.py:500-554`) is the ONLY drop check in
  the shipped "replace" mode and now needs a raw measurement within
  max_track_age: a dropped ball hidden by the base/floor ends no attempt
  (manual abort). Options: `mode: supplement`, or surface the skipped-
  candidate counter above DEBUG. Sim has no occlusion.
- Seven axes changed since the last recorded hardware run (kd 0, park
  +3 cm, planning lead 60 ms, pre-touchdown cone [0.05], post-0 inert,
  min-sep every other knot, send advance 10 ms): each justified in sim,
  none validated on hardware -> first session is a shakedown.

PREFLIGHT (add to preflight.sh / run_next, see below)
- AOT: gcc/g++ present in the running container, `/retain/tp_nlp_aot`
  writable, startup log shows `AOT: N compiled, 0 failed` BEFORE attempt 1.
  planning_lead 0.060 is sized for compiled solves (worst 45 ms);
  interpreted worst is 58-73 ms -> negative margin -> SendDeadlineMissed.
  A cold compile is ~43 x 40 s gcc at cores-4 jobs with the driver live.
- Tracker checkout on ball = the branch above.

AUDIT FINDINGS NOT ON THE ROBOT PATH (do later)
- Three DR samplers: `environment/domain_randomization.py` (direct MuJoCo,
  JRL_DR_*), `utils/plant_randomisation.py` (ROS, the one to use), and an
  inline heredoc in `scripts/overnight_robustness.sh:70-93` that sets the
  controller URDF to the SAME drawn mass/length as the plant -- no mismatch
  on those axes, only tilt (+ cup radius, which Kai holds fixed). Any
  `_night/dr*` number is mislabelled. Port the script onto
  plant_randomisation; document the direct-MuJoCo one as legacy.
- `env_knobs.KNOBS` misses 21 of ~34 env reads (5 on the hardware send
  path: JRL_SEND_ABORT_MARGIN_S, JRL_CMD_QUEUE_SIZE, JRL_STATE_TOPIC_SUFFIX,
  ...; all JRL_DR_*; TP_NLP_AOT_MAX_*). `TP_NLP_AOT_DIR` is never read and
  `TP_NLP_AOT=0` cannot disable AOT (cfg bool wins). Needs a discovery test.
- `app_id_association/run.py` duplicates launch()/write_arm_config() from
  the sibling harness it imports from (~40 lines, drifted).
- Morning audit #2 still open: hand-typed cup geometry in two scripts;
  `plant_randomisation.nominal_from_cfg()` is the drop-in.
- Test suite inherits the AOT compile (6 juggler-building test files write
  to the live /retain cache; gcc on the box during timed runs). Measure.
- `catch_hand_velocity.only_after_zero` is honoured by SiteswapJuggler only;
  the planner ignores the key (an unscoped use would silently be all-catch).
- Stray 26 MB worktree `_worktrees/_um_test` double-counts workspace greps.

### 2026-09-11 21:23 — the shipped default stack, confirmed as ONE stack (robot config for 2026-09-12)

`_probe/bisect_final_default` (default chain): 6/8 `✗✗✓✓✓✓✓✓` (drops at 18,
50 in attempts 1-2, then clean to 89; 0 late sends; planning max 57.7 with
the rest at 31-34). `_probe/bisect_final_held` (--hold-0s --hold-2s, no
overlay): 8/8, throw 89, planning max 26.6. Stack: kd 0, park +3 cm on 0
beats, post-0 inert, planning lead 60 ms, send advance 10 ms, held-2
touchdown constraint, tracker posterior + velocity 0.10 + penalty 0, AOT.
Within the day's spread for the same chain (7/8-8/8 with attempt-1 drops).

## Done

_(nothing yet)_

## Tracker: a NEW track created from a future-stamped update still sets its clock ahead

`multi_ball_tracker_impl.hpp`, PHASE 2 of `processApplicationUpdates` — when an
application update matches no existing track, a track is created and
`kalman.initialize(..., update.timestamp, ...)` sets the filter's clock to that
stamp. Publishers lead by `TRACK_UPDATE_LEAD_S` (0.050 s), so that stamp can be an
instant that has not happened.

Existing tracks no longer have this problem: a future-stamped reset waits in
`BallTrack::pendingReset` and is applied by `processMeasurementFrame` when the frame
clock reaches it. A brand-new track cannot use that buffer — there is no prior state
to hold the reset away from — so the fix would be to defer the track's CREATION
instead, or to back-propagate the state to the current frame time (exact for
CONSTANT_POSITION / VELOCITY / ACCELERATION, awkward for CONSTANT_DRAG).

MEASURED, smoke3 in ros_sim on 2026-09-09: `new_track_future=3` against
`deferred=130` in the same run, i.e. about 2% of state resets. Counted by
`newTracksFromFutureStamp_`, which also logs a warning naming the lead in ms.
Left unfixed because it is rare and the machinery is not small; the counter is there
so it can be re-checked rather than assumed.

## The pre-touchdown cone's knot window is a constant where it should be derived

`jugglers/config.py`, `pre_touchdown_cone.interpolation_breakpoint_range`.
`Trajectory.interpolate_q` CLAMPS the evaluation time into this window and builds
one if_else branch per interval inside it, so the window must span every time the
cone is evaluated at — too narrow is a silently wrong constraint, too wide is
graph cost in every solve.

It has to cover `t_catch - t_before_contact ± max_time_adaptation`, where
`t_catch = (1 - dwell_ratio) * cycle_time`, over every tempo in the chain. That
is four cfg values, and the window is one hardcoded pair. Measured widths
(2026-09-09, tempos 0.43–0.60, `t_before_contact` {0.05, 0.10}):

    dwell        adaptation   required     intervals
    0.42         0 ms         [10, 15]      5      <- the old value, exactly
    0.42         20 ms        [ 9, 16]      7
    0.50         20 ms        [ 6, 14]      8
    0.42-0.50    20 ms        [ 6, 16]     10      <- set today
    0.42-0.50    50 ms        [ 4, 18]     14

The old `[10, 15]` was "dwell 0.42, adaptation OFF" — sized as if catch-time
adaptation did not exist, while `adapt_catch_time` is True at 20 ms. It had been
clamping at the tempos this study runs.

OPEN: `CatchAdaptationCfg.max_time_adaptation` defaults to **0.05**, which needs
`[4, 18]`; the study narrows it to 0.02 via
`experiments/transitions/configs/best_chain_catch_clamp.yaml:19`, which `[6, 16]`
covers. So real runs are fine and a factory-default run is not.
`tests/test_breakpoint_range_envelope.py::test_the_factory_adaptation_limit_does_not_exceed_the_window`
xfails on exactly this so it stays visible.

Proper fix: derive the window per tempo and per trajectory variant at NLP-build
time from `n_time_steps`, `cycle_time`, `dwell_ratio`, `t_before_contact` and
`max_time_adaptation`, instead of one constant sized for the worst case across
the whole chain. At a single tempo and dwell the honest window is 5 intervals
against the 10 we now carry, so this is worth real solve time — see the
planning-speed work.

## [x] ALL solves must leave the main process — DONE 2026-09-09

Kai, 2026-09-09, after being informed: "We need to get ALL of the solves to out
of the main process."

MEASURED, ros_sim smoke3: 168 of 174 solves route to the pinned subprocess
workers (cores 22/23). Six do not — two per attempt: **`cyclic_from_rest` and
`cyclic_stop`**.

WHY they stay in-process. `siteswap_juggler.py:1511` / `:1523` (and `:1556` for
the per-duration stop variants) call `planner.build_throw_nlp(...)` /
`planner.build_stop_nlp(...)` **directly on the planner object**, bypassing the
`planner_bank` helpers that call `_record_nlp_build`. With no recorded build
step, `unsupported_worker_builds` flags them and `HybridSolverBackend` keeps
them in-process rather than giving up worker isolation for the whole run.

WHY SIX OUT OF 174 MATTERS — Kai's observation, and it explains a symptom we
chased all day. `cyclic_stop` is the STOPPING plan, and stopping is exactly what
happens when a ball drops. So the in-process GIL hold lands precisely when the
remaining balls' expected-state updates are due. That is the delayed tracker
updates after a drop. The six fire at the worst possible instant.

Recorded evidence that in-process solving is harmful, from `solver_backend.py`:
94% of trajectory sends arriving AFTER their own start time (mean −11.2 ms) and
the driver answering "Rejecting trajectory - transition time is in the past" —
a rejected trajectory means the arm never moves and the attempt collapses with
one arm frozen. That measurement is why `HybridSolverBackend` exists.

THE PAYOFF once it lands: `TRACK_UPDATE_LEAD_S` (0.050 — how far ahead expected
states are published to the tracker) exists to absorb exactly this jitter.
Kai expects it can come down to ~0.010 once no solve blocks the main process.
Measure it; do not assume it.

THE TRAP in fixing it: the replayed NLP must be IDENTICAL to today's.
`cyclic_stop` is built with a REDUCED constraint set — only `joint_limits`, not
the full `catch_and_stop` `constraint_params` — plus its own `np.linspace` grid;
`cyclic_from_rest` uses `first_throw`'s constraints over a custom `throw_span`.
Routing them through the existing recorded helpers would re-derive both from cfg
and silently build a DIFFERENT NLP — changing recorded numbers with nothing
failing. The safe shape is to record the build with its explicit arguments
(time-steps array, constraint_configs dict, cost-function selector, key) and
replay those, rather than re-deriving from cfg.

RESOLVED in `72ea834`, 24 minutes after this was written: `_build_explicit_nlp`
records the build, and both `siteswap_juggler.py` call sites go through it, so
`unsupported_worker_builds()` is now empty and no direct
`planner.build_throw_nlp` / `build_stop_nlp` calls remain.
`tests/test_all_nlps_are_worker_replayable.py` pins it.

WHAT REMAINS IS NOT WHAT THIS ITEM DESCRIBED, and the difference matters.
Measured with a per-process, per-key tally: the juggler still solves each NLP
key exactly ONCE, at startup — 6 keys on smoke3, 42 on cascade5 (one per tempo
variant per arm). It scales with the NUMBER OF NLPs rather than with throws,
and none run during juggling. So it is initialisation priming, not the
stop-plan-during-a-drop this item hypothesised. The hypothesis that
`cyclic_stop` holds the GIL exactly when a ball drops is NOT supported by the
data.

## 2026-09-10 — chain regression: RESOLVED 2026-09-11 (pre-touchdown cone), plus gain 0.8

**Resolved:** the regression was the pre-touchdown cone trimmed to [0.1]. One
point at [0.05] gives 7/8 (`.SSSSSSS`) on the shipped config; [0.05, 0.1]
gave 2/8; [0.1] gave 0/8. Committed as the default. The items below stand as
the evidence trail and for the other findings (gain, alpha, arm-done gate).

**The chain's dominant failure is one beat, not tracking.** Every drop across
every configuration today followed `ssbank_*_i5_p5_o4_t50` (the 4-throw of
504 catching a 5), first right hand, later left. Ground truth
(`_probe/gtdrop`, `experiments/analysis/plot_gt_vs_tracker.py`) shows
tracking ~1 mm accurate through the whole attempt and touchdown prediction
median 6 mm / p90 14 mm over 74 catches — the hand knows where the ball is
and still misses. The ball that failed sat at x=0.643 vs nominal 0.493:
exactly the 0.150 m catch clamp. Balls arriving 0.27 m long are unreachable
however good the prediction. Evidence: `_probe/gtdrop/attempt1.png`,
`_probe/gtdrop/fail_closeup.mp4`, `/tmp/predcheck.py` output in session.

**Splice replanning after a 0 beat is suspect (Kai's read of the video).**
The beat that starts from a 0 carries `px` in its key
(`ssbank_right_i4_px_o5_t50`) and took 6 spliced replans; its tail is the
arm state the failing catch inherits. Replan off moved the failure from
throw 62 to 74 but did not remove it. The 0 beat itself is correctly
excluded (`throw_kind is ThrowKind.CATCH_AND_THROW`, throw_scheduler.py
~L982); the beat AFTER it is not. Unresolved: whether the splice offset is
computed against the wrong nominal for a `px` beat, or
`_catch_offsets_for_key` is wrong for a beat with no incoming throw.

**Gain 0.8 works; 1.0 and 0.0 do not.** Same chain, seed 0, 88 throws:
  gain 1.0 + replan        0/8   (throw 61)
  gain 1.0, no replan      0/8   (throw 73)
  gain 0.0, no replan      0/30  (best 83, no convergence; resumed to 60)
  gain 0.8, no replan      3/10  shape `...SSS....` — succeeds at 4-6, then
                           regresses; late failures on the same
                           `i5_p5_o4` beat, now left hand.
Config: `experiments/real_robot/siteswap_sequence/configs/_gain080.yaml`.
The regression after three successes is unexplained — candidate: the
beat-keyed `ssbeat_b41_left` learners at alpha 0.8 random-walking on one
sample per attempt (`_ab_beat_alpha.yaml` exists and has never been run).

**planning_lead must be derived from hundreds of plans.** 0.070 was set
from a max of 37.9 ms over 149 plans; a 30-attempt run produced 58.0 ms.
Now 0.090. The max of a heavy-tailed solve distribution grows with sample
size; ~150 plans under-samples it.

**Still queued behind the sim:** `scripts/collision_744_test.sh` (5 -> 744,
collisions on, validates the collision detector on a known pair), and the
seven `experiments/app_id_association` arms with collisions OFF and 20
attempts (only 2 of 7 have ever run, both on a scenario that never reached
5 balls).

**`ends_arm_for_attempt` keys off the throw TYPE prefix `catch_and_stop`;
on the cascade path a mid-pattern held 2 would get the same label.**
`cascade_juggler.py` `_schedule_cascade_throw`: the ending stop is
`f'{THROW_TYPE_CATCH_AND_STOP}_{arm}'` and a non-stop no-release beat is
`f'{cyclic_kind.label}_{arm}'` -- for a held 2 the kind is CATCH_AND_STOP,
label "catch_and_stop", same string. Harmless today: uniform cascades have
no 2s, and the siteswap path schedules pattern beats under bank keys
(`ssbank_*`, `ssbeat_*`, `toss_no_ball_*`), never `catch_and_stop_*`
mid-pattern (every log today). The clean fix is an explicit `is_stop`
argument on `_schedule_throw` rather than a name test. Evidence: 530a32e,
logs in `_probe/gtdrop/run.log` lines 6761-6798.

## 2026-09-11 — full-tree review, items not fixed today (report: .claude/reviews/full-2026-09-11.md)

Fixed the same day: the 16-file cfg stack (now `experiments/_shared/chain_cfg_stack.sh`),
the env-only donor knobs (now JugglerCfg fields), ball_collisions.py wired into the
attempt-result funnel. Remaining, with the review's recommendation:

- **Tool geometry hand-typed in `scripts/catchup_queue.sh` and
  `scripts/overnight_robustness.sh`** instead of derived via
  `tool_args_from_arm_cfg`/`build_launch_command` from `_zoo_tool()`. Same
  failure class as the fixed `ros_sim_health.sh --force` plant swap.
  `overnight_robustness.sh` perturbs those constants for DR, so the fix is to
  derive the nominal args and apply the perturbation as launch-arg overrides.
- **Dead since the 2026-08-27 review:** `jugglers/siteswap_warm_starts.py`,
  `experiments/analysis/replication.py`. Delete or state the intended caller —
  Kai's call.
- **`juggling_rl/robot_description` ~3 months stale** vs
  `juggling_residual_learning/robot_description` (independent checkouts, not a
  submodule). Kai's call whether juggling_rl should track it.
- **Fountain jugglers still hand-copy the cyclic throw loop** (3rd consecutive
  review). Large; the `is_stop` change today had to touch all three siblings.
- **`PlannerBankMixin` +827/−31 lines in two weeks**: NLP build, warm-start
  banking, replan grid, cache seeding, worker spec and plan dispatch in one
  mixin. Proposed split in the report (build / warm-start+cache / dispatch).
  Large; weigh against the thesis timeline.

**Build-time safety fallbacks: ~1,200 per run, silently replacing tempo-variant
warm starts with the nominal reference (2026-09-11).** On the 7/8 default run,
1,212 of 1,223 "Safety fallback triggered" lines fire BEFORE attempt 1, on the
per-tempo keys (`catch_and_throw@0.480/0.492/0.504/0.529/0.554`, ~120 each,
plus `catch_and_throw_replan@8` x132). Violation is always `q`: max_abs 0.95
against a 0.7 threshold (the chain's `best_chain_envelope` value). Without
strict_fallback the plan is "quietly substituted with the nominal reference"
(planner_bank.py `SafetyFallbackError` docstring), so those tempo variants
run on the reference, not the solved warm start -- and 1,200 lines of noise
hide any real veto. Decide: exempt the build phase from the q envelope, size
it per tempo, or raise 0.7. Evidence: `_probe/bisect_default_confirm/run.log`.
