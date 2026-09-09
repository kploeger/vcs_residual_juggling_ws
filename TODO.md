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

---

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

## ALL solves must leave the main process — 2 per attempt still do not

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

Assigned to the planning-speed agent, which already owns `planner_bank.py` and
`solver_backend.py`.
