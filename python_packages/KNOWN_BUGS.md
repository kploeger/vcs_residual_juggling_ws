# Known bugs

Bugs noticed but deliberately not fixed yet. Each entry cites `file:line`,
describes the problem, proposes a fix, and says why it was deferred.

---

## `release_fit_min_fit_points` is silently clamped to 6

**Where:** `juggling_residual_learning/juggling_residual_learning/label_generator.py:275`

```python
min_pts = max(int(self.release_fit_min_fit_points), 6)
```

`_keep_ballistic_inliers` floors the configured minimum at 6, so a config
asking for 4 silently gets 6. Nothing warns, so a tuned-looking config is
not the config in force. This is the same family as the `--learner-type`
override and the render-preset override: an explicit setting discarded
without a word.

It currently breaks one test.
`tests/test_early_flight_fallback.py::test_velocity_offset_learner_uses_fallback_when_descent_data_is_missing`
configures `release_fit_min_fit_points=4` and supplies 7 samples; the trim
loop drops 2 outliers, leaving 5, and `5 < 6` rejects the window, so
`evaluation_method` comes back `None` instead of `"release_fit"`. This is a
REGRESSION, not a stale test: the test dates from 911fcdf (2026-05-08) and
the floor arrived in 527c004 (2026-08-12), a large mixed commit.

**But the floor may well be right.** Reproducing the trim loop on that
measurement set:

    min_pts=4: 5 survivors, rmse=0.00350, recovered g=-7.834 -> accepted
    min_pts=6: 5 survivors, rmse=0.00615, recovered g=-7.846 -> rejected

At 5 points the fit recovers gravity as -7.83 against a true -9.81 — 20%
off, passing only because the gate tolerates 25%. Fitting 3 coefficients
through 5 points after trimming 2 is thin, and rejecting it is defensible.

**Proposed fix**, once someone decides which behaviour is wanted:

* If 6 is a genuine floor: validate `release_fit_min_fit_points` at
  construction and raise (or warn once) when a smaller value is configured,
  instead of clamping in silence — then update the test to supply enough
  samples for the early-flight fallback it is actually about.
* If the config should win: drop the `max(..., 6)` and rely on the RMSE and
  gravity gates, possibly tightening the gravity tolerance from 25%, which
  is loose enough to admit the -7.83 fit above.

**Why deferred:** this is the label-generation path that every learner's
evaluation depends on, and the choice is a research judgement about how much
early-flight data the fallback must tolerate — not a call to make while
working on something else. Flagged to Kai 2026-08-24.

## Intermittent heap corruption / core dump in long chain runs

**Status:** open. Observed 2026-08-25, five occurrences in one night.

`learn_40__siteswap.py` on segment chains intermittently dies with
`corrupted size vs. prev_size` followed by `timeout: the monitored command
dumped core`. Affected logs that night: `chain45lowdrop`, `chain345ol30`,
`chain345recheck`, `chain345gate`, `chain345ros_reset`.

**Not resource pressure.** It happens with ~31 GB of 62 GB used and load
well under the 24 cores; it also happened on an otherwise idle machine, not
just during the 3-4 way parallel sweeps.

Two flavours, and the difference matters when reading results:

- **at teardown**, after the run's own success summary has printed. The
  result is complete and valid (e.g. `chain345gate` reported 6/30 and then
  dumped core). Easy to mistake for a failed experiment.
- **mid-run**, losing the remaining attempts (`chain345ol30` died after 5 of
  30). The harness reports whatever attempts completed, so a truncated run
  can be silently under-powered -- check the attempt count against what was
  requested before quoting a rate.

`corrupted size vs. prev_size` is glibc detecting heap metadata damage, so
the corruption happens earlier than the abort and the stack at death is not
the culprit. Suspects worth eliminating: the MuJoCo python bindings under
repeated model/data construction across attempts, and the solver subprocess
backend's teardown path (`solver_worker.py`).

**Partial mitigation landed** (`learn_40__siteswap.py`, via
`runners/learner_args.truncation_report`): the runner now compares completed
attempts against `attempts x runs` and exits 2 with a message naming both
counts, so a truncated run can no longer be quoted as a complete one. A
deliberate interrupt reports the shortfall but stays exit 0. The cascade
runners (`learn_30/31/32`) print the same style of success rate and should
adopt it too.

**The crash itself is unfixed** -- the guard only stops it corrupting
results silently.

---

## `robot_control` uses the full crba mass matrix without symmetrising

`robot_control/robot_control/control.py:225` does

```python
M = pin.crba(self.model, self.data, q)
... nan_to_zero(M @ ddq_des) ...
```

and consumes the **full** matrix. Historically `crba` fills only the UPPER
triangle of `data.M` and leaves the lower triangle undefined, which is why
`juggling_residual_learning/model_consistency.py:188` symmetrises
explicitly with the comment "crba fills upper only".

**Currently harmless, and measured to be so.** On the pinocchio this
workspace pins (3.4.0), the Python binding returns a fully symmetric
matrix: `max |M - M^T| = 0.0` across 50 random configurations of the sample
manipulator and 20 of the sample humanoid, and the lower triangle is
populated. So `M @ ddq_des` is correct today and adding a symmetrisation
would be a pure no-op cost inside a 1 kHz control loop.

**Why it is still worth recording:** the correctness of that line is a
property of the pinocchio version, not of the code. On any pinocchio where
`crba` fills upper-only, `M @ ddq_des` silently uses undefined values below
the diagonal — wrong torques, no crash, no warning. The neighbouring
`jax_juggling_ros_ws` session measured exactly that asymmetry from the
**C++** side of `robot_controllers`
(`detail/robot_model-inl.hpp:61`, `massMatrix()` returning `crba(...)` raw):
`max |M - M^T| = 6.71` on pinocchio's sample manipulator at q = 0. Same
library, same call, opposite result — so the two language bindings and/or
the two containers' pinocchio versions do not agree, and one of them fills
upper-only.

**Proposed fix (deferred):** either symmetrise at the call site

```python
M = np.triu(M) + np.triu(M, 1).T
```

or, better and free, assert the symmetry ONCE at controller construction
rather than per control step, so a pinocchio upgrade that reintroduces
upper-only fails loudly at startup instead of quietly producing wrong
torques for a whole campaign.

**Why deferred:** no defect exists at the pinned version, the hot path
should not pay for a no-op, and the real question — which pinocchio fills
upper-only — is still open with the neighbouring workspace.

**Note:** `robot_controllers` (C++, generic package) has the same pattern
at `detail/robot_model-inl.hpp:61` and `:153`. residual_ws has **no**
caller of `massMatrix` / `massMatrixInverse` — the only references are the
package's own test — so fixing it there cannot affect this workspace.

---

## Killed runs leak zombie processes in the `rwam` container

Observed 2026-08-25: **177 defunct `python3` processes** in `rwam`, all with
PPID 1, accumulated over a day of starting and killing experiment runs.

They cost no CPU and no memory -- a zombie is just an exit status waiting to
be reaped -- so they are not a performance problem. They consume PID slots,
and the count only grows.

**Cause.** The solver backend spawns subprocess workers
(`solver_backend`/`solver_worker.py`, "solves routed: {'subprocess': N}").
When a run is killed rather than exiting cleanly, those children are orphaned
and reparented to PID 1. The container's PID 1 is not an init that reaps, so
they stay defunct forever.

**Why it matters, mildly:** a long-lived container plus many killed runs will
eventually exhaust the PID namespace. At 177 after one heavy day it is not
close, but nothing clears them short of a container restart, and `rwam` is
deliberately long-lived (up 24h+).

**Fixes, none applied:**
* run the container with `--init` (or `--pid=host`), so PID 1 reaps orphans;
* or have the solver pool install a SIGTERM handler that terminates its
  workers before exiting, so they are never orphaned in the first place.

**Why deferred:** the first is a container-lifecycle change and Kai owns
that; the second is a real fix but touches the solver backend, which is on
the hot path for every run, and the symptom is currently benign. Worth doing
the SIGTERM handler when the solver backend is next touched for another
reason.

## Dead optional hook: `_update_desired_ball_mocaps`

`juggling_residual_learning/jugglers/launchers.py:696-700` calls
`self._update_desired_ball_mocaps(t_launch_time)` behind a
`hasattr(self, ...)` guard. Nothing in the workspace defines that method, so
the guard is always False and the block never runs — the launcher never
updates desired-ball mocaps at release, and no caller can tell.

Found by `tests/test_no_calls_to_removed_methods.py` (2026-08-28), which
scans for `self._foo()` with no definition anywhere. The test exempts
hasattr-guarded calls, since that is the legitimate optional-hook pattern —
so this one is exempt and will stay invisible to it.

**Proposed fix:** either implement the hook, or delete the guarded block and
the log message that goes with it. Deciding needs to know whether desired-ball
mocap visualisation at launcher release was ever wanted; that is a
visualisation concern, not a correctness one.

**Why deferred:** harmless (it is a no-op, not a wrong result), unrelated to
the ROS execution work in flight, and removing it would touch the launcher
path during an active investigation of launcher-fed catches.

