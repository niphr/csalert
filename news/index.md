# Changelog

## Version 2026.7.1

### Simplification

- **`reporting_completion_trend_v1`** returns the completion curve by
  calendar year (all) + by month (last N, per series) with a `scope`
  column – the year/month trend that the luftveis pipeline used to
  assemble by hand.
- **`nowcast_evaluate_v1`** is now the single entry point for scoring
  nowcasts: give it a triangle and one method (or a NAMED list), and it
  replays each – paired by a shared `seed` – and returns one per-horizon
  table of interval coverage + point-estimate revision, with a `method`
  column. It subsumes the former `nowcast_score` (coverage, via
  scoringutils), `nowcast_revision`, `nowcast_compare` and
  `nowcast_validate`; coverage is read straight off the interval
  quantiles, so **`scoringutils` is no longer a dependency** (WIS was
  dropped).
- Removed the unused **`nowcast_survrtrunc_v1`** engine (and its
  `flexsurv` dependency) and the conformal **calibration** functions
  (`nowcast_estimate_calibration_v1` / `_apply_` /
  `print.nowcast_calibration`) — both had been dropped from the
  production pipeline.
- Renamed `mem_thresholds` -\> **`mem_thresholds_v1`** (versioned-engine
  convention).

### Documentation

- New vignette **“Nowcasting a reporting triangle with
  csfmt_ensemble_v3”** — a runnable end-to-end walk-through (synthetic
  triangle -\> nowcast -\> collapse -\> backtest
  coverage/revision/completion -\> naming grammar).
- Documented the previously-bare `print.csfmt_ensemble_v3` method; added
  the missing `@returns` to the ensemble/nowcast S3 methods
  (`mem_thresholds_v1`, `short_term_trend`, `signal_detection_hlm`,
  `nowcast_quasipoisson_v1`).
- Added runnable `@examples` to the naming-grammar functions
  (`csfmt_var`, `csfmt_parse`, `q_label`, `q_value`) and to the nowcast
  analysis functions (`nowcast_evaluate_v1`,
  `reporting_completion_trend_v1`).
- Fixed unescaped `%` in the nowcast / `reporting_completion` roxygen
  that had been corrupting their generated `.Rd`, plus copy-paste errors
  in the simulation-helper docs.

### csfmt_ensemble_v3 surveillance engine

A new draw-parallel ensemble format and the full analysis pipeline built
on it (reporting triangle -\> nowcast -\> trend -\> MEM thresholds -\>
quantile collapse).

- `csfmt_ensemble_v3`: S3 container (`$data` data.table + per-measure
  `$draws` matrices) with invariants enforced by `validate_ensemble`.
- Naming grammar: `csfmt_var` / `csfmt_parse` (order-independent parse
  of trailing coordinates), `q_label` / `q_value`, and `csfmt_interpret`
  for self-describing datasets.
- `csfmt_reporting_triangle_v3`: reference-by-delay input format with a
  reshape that completes the reference axis.
- `nowcast()`: reporting triangle -\> ensemble via flexsurv
  `survrtrunc` + negbin (no epinowcast dependency). Can nowcast a
  denominator alongside the numerator (full % positive -\> MEM path) and
  surface the observed denominator total. The reporting-before-reference
  check is NA-safe.
- `observed_ensemble()`: passthrough (degenerate single-draw) ensemble
  for indicators that should not be nowcasted.
- `collapse()`: ensemble -\> quantile summary; `collapse(heal = TRUE)`
  heals the result into cstidy `csfmt_rts_data_v3`.
- `add_rate()`: numerator-vs-denominator rate (% positive).
- `short_term_trend.csfmt_ensemble`: batched, shared-design-matrix
  kernel that also emits P(increasing).
- `mem_thresholds.csfmt_ensemble_v3`: MEM intensity thresholds with
  provisional seasons; `exclude_seasons` drops anomalous seasons from
  the baseline; training is capped to the most recent `i.seasons` before
  `na.omit`; a non-zero-season guard plus a quiet `memmodel` wrapper
  prevent sparse indicators from erroring.
- `signal_detection_hlm.csfmt_ensemble_v3`: per-draw exceedance
  detection.
- `add_holiday_effect` for the ensemble format.
- Input QC: `qc_surveillance_data` (generic input QC, verdict only) and
  `qc_week_over_week` (A/B revision comparison across runs).
- `add_rate` and `collapse` are renamed to `ens_add_rate` /
  `ens_collapse` and are now S3 generics dispatching on
  `csfmt_ensemble_v3` (the `ens_` family), so the ensemble class carries
  the “operates on an ensemble” meaning. Behaviour is unchanged.
  (`add_holiday_effect` is a simulation-data helper on a plain
  data.table and keeps its name.)
- `nowcast` and `observed_ensemble` are renamed to
  `nowcast_survrtrunc_v1` and `nowcast_passthrough_to_ensemble_v1` –
  concrete, VERSIONED nowcast engines that share the contract
  `f(reporting_triangle, ...) -> csfmt_ensemble_v3`. Behaviour is
  unchanged; the `_vN` suffix versions the algorithm (a future
  `nowcast_stan_v1` or `nowcast_simple_v2` slots in beside them),
  selected by a caller-side registry. The validation harness
  (nowcast_backtest/score/compare/validate/censor/truth) is generic
  tooling and is NOT versioned.
- `nowcast_survrtrunc_v1` gains `delay_window` (default 26 weeks): the
  reporting-delay distribution is estimated from only the most recent
  weeks, so a non-stationary / drifting delay (e.g. a backfilled history
  then live prospective reporting) is tracked instead of averaged into a
  stale pooled curve. Fixes the median bias that caused sub-nominal
  interval coverage; residual under-coverage (plug-in delay) is
  documented by the calibration test and awaits per-draw delay
  uncertainty or backtest-driven recalibration. `NULL` restores the old
  pool-all-history behaviour.
- Calibration test (`test-nowcast-calibration.R`): empirical interval
  coverage vs nominal on synthetic data, with a stationary case
  (calibrated) and a drifting-delay case (reproduces the real-data
  under-coverage synthetically).
- `nowcast_simple_v1` renamed to `nowcast_survrtrunc_v1` (the name now
  states the method: right-truncated survival delay + negbin
  completion).
- New engine `nowcast_quasipoisson_v1`: a discriminative (regression)
  nowcast – for each horizon, regress the settled TOTAL on the counts
  reported so far (`total ~ n[delay 0] + n[delay 1] + ...`,
  quasipoisson/identity, no intercept) on the recent settled weeks, then
  simulate the incomplete weeks (parameter uncertainty from the fit + a
  dispersion-matched negbin). No per-week magnitude parameter, so it is
  robust for the recent weeks and honestly dispersed – drifting-delay
  synthetic coverage ~0.79 vs the plug-in survrtrunc’s ~0.72 (nominal
  0.90). Base stats only; same `f(triangle) -> ensemble` contract -\>
  drops into the registry as a candidate key.
- Backtest-driven recalibration: `nowcast_estimate_calibration_v1`
  learns a per-group (default horizon) conformal interval-scaling
  correction from past nowcasts vs settled truth, and
  `nowcast_apply_calibration_v1` applies it so a method’s intervals hit
  nominal coverage regardless of internal misspecification (a
  `nowcast_calibration` S3 object with a print method sits between).
  Turns the backtest into calibration data: engine -\> backtest -\>
  estimate -\> apply -\> honest intervals. Distribution-free (split
  conformal); estimate on past backtests, apply to the current nowcast.
- Nowcast validation harness (method-agnostic, replay-based):
  `nowcast_censor` (reconstruct what was known as-of a past week from
  the reporting triangle), `nowcast_truth` (settled totals),
  `nowcast_backtest` (replay any `f(triangle) -> ensemble` across as-of
  weeks into tidy quantile nowcasts), and `nowcast_evaluate_v1` (score
  one or several methods on interval coverage + point-estimate revision
  by horizon – see the Simplification section above).
- `reporting_completion`: the empirical reporting-delay summary of a
  triangle – from the settled weeks, the mean delay, the weeks-observed
  to reach 25/50/75/90/95% of a reference week’s cases, and the fraction
  actually in by `max_delay`. `period = "year"` / `"month"` stratifies
  the settled weeks in time (by the ISO year / midweek-day month) so a
  drift in reporting speed shows up as a trend in mean delay instead of
  being averaged away.

## version 2024.6.24

CRAN release: 2024-06-24

- Inclusion of short_term_trend_sts_v1.

## Version 2023.6.22

- First inclusion of signal_detection_hlm.

## Version 2023.5.23

- Updating to be in line with the latest cstidy version.

## Version 2022.5.6

- short_term_trend now allows for vectorized prX and
  statistics_naming_prefix.

## Version 2022.4.22

- short_term_trend now allows for granularity_time==‘isoweek’ and
  denominators.

## Version 2022.4.21

- short_term_trend created to allow for easy estimation of short-term
  trends (increasing/decreasing/null), doubling time in days, and
  short-term forecasting with prediction intervals.
- prediction_interval created to allow for easy estimation of prediction
  intervals after fitting glms (family = poisson and quasipoisson) based
  on Farrington 1996.

## Version 2022.4.10

- Package is created
