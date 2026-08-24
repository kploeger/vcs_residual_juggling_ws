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
