# Version 2026.7.1

## csfmt_ensemble_v3 surveillance engine

A new draw-parallel ensemble format and the full analysis pipeline built on it
(reporting triangle -> nowcast -> trend -> MEM thresholds -> quantile collapse).

- `csfmt_ensemble_v3`: S3 container (`$data` data.table + per-measure `$draws`
  matrices) with invariants enforced by `validate_ensemble`.
- Naming grammar: `csfmt_var` / `csfmt_parse` (order-independent parse of
  trailing coordinates), `q_label` / `q_value`, and `csfmt_interpret` for
  self-describing datasets.
- `csfmt_reporting_triangle_v3`: reference-by-delay input format with a reshape
  that completes the reference axis.
- `nowcast()`: reporting triangle -> ensemble via flexsurv `survrtrunc` + negbin
  (no epinowcast dependency). Can nowcast a denominator alongside the numerator
  (full % positive -> MEM path) and surface the observed denominator total. The
  reporting-before-reference check is NA-safe.
- `observed_ensemble()`: passthrough (degenerate single-draw) ensemble for
  indicators that should not be nowcasted.
- `collapse()`: ensemble -> quantile summary; `collapse(heal = TRUE)` heals the
  result into cstidy `csfmt_rts_data_v3`.
- `add_rate()`: numerator-vs-denominator rate (% positive).
- `short_term_trend.csfmt_ensemble`: batched, shared-design-matrix kernel that
  also emits P(increasing).
- `mem_thresholds.csfmt_ensemble_v3`: MEM intensity thresholds with provisional
  seasons; `exclude_seasons` drops anomalous seasons from the baseline; training
  is capped to the most recent `i.seasons` before `na.omit`; a non-zero-season
  guard plus a quiet `memmodel` wrapper prevent sparse indicators from erroring.
- `signal_detection_hlm.csfmt_ensemble_v3`: per-draw exceedance detection.
- `add_holiday_effect` for the ensemble format.
- Input QC: `qc_surveillance_data` (generic input QC, verdict only) and
  `qc_week_over_week` (A/B revision comparison across runs).
- `add_rate` and `collapse` are renamed to `ens_add_rate` / `ens_collapse` and
  are now S3 generics dispatching on `csfmt_ensemble_v3` (the `ens_` family), so
  the ensemble class carries the "operates on an ensemble" meaning. Behaviour is
  unchanged. (`add_holiday_effect` is a simulation-data helper on a plain
  data.table and keeps its name.)
- `nowcast` and `observed_ensemble` are renamed to `nowcast_simple_v1` and
  `nowcast_passthrough_to_ensemble_v1` -- concrete, VERSIONED nowcast engines that
  share the contract `f(reporting_triangle, ...) -> csfmt_ensemble_v3`. Behaviour
  is unchanged; the `_vN` suffix versions the algorithm (a future `nowcast_stan_v1`
  or `nowcast_simple_v2` slots in beside them), selected by a caller-side registry.
  The validation harness (nowcast_backtest/score/compare/validate/censor/truth) is
  generic tooling and is NOT versioned.
- Nowcast validation/comparison harness (method-agnostic, replay-based):
  `nowcast_censor` (reconstruct what was known as-of a past week from the
  reporting triangle), `nowcast_truth` (settled totals), `nowcast_backtest`
  (replay any `f(triangle) -> ensemble` across as-of weeks into tidy quantile
  nowcasts), `nowcast_score` (WIS + interval coverage by horizon via
  `scoringutils`), and `nowcast_compare` (rank engines head-to-head, e.g. a real
  nowcast vs the passthrough baseline). `scoringutils` added to Suggests.

# version 2024.6.24

- Inclusion of short_term_trend_sts_v1.

# Version 2023.6.22

- First inclusion of signal_detection_hlm.

# Version 2023.5.23

- Updating to be in line with the latest cstidy version.

# Version 2022.5.6

- short_term_trend now allows for vectorized prX and statistics_naming_prefix.

# Version 2022.4.22

- short_term_trend now allows for granularity_time=='isoweek' and denominators.

# Version 2022.4.21

- short_term_trend created to allow for easy estimation of short-term trends (increasing/decreasing/null), doubling time in days, and short-term forecasting with prediction intervals.
- prediction_interval created to allow for easy estimation of prediction intervals after fitting glms (family = poisson and quasipoisson) based on Farrington 1996.

# Version 2022.4.10

- Package is created
