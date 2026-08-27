# Version 2026.8.27

## Breaking: `propagate_slope_error` was removed, and the slope error is always propagated

- **`short_term_trend()` on a `csfmt_ensemble_v3` no longer takes
  `propagate_slope_error`.** The slope's own sampling error now reaches every
  draw, always, and there is no way to switch it off.
- Two things are uncertain and both belong in the draws: the **level**, which
  the incoming ensemble already carries, and the **line** fitted through those
  levels. `increasing_pr` is the share of draws whose slope is positive, so
  without the second it is a sign test on the point slope wearing the name of a
  probability. A threshold like `> 0.975` on it then does nothing at all. That
  was the default behaviour, and nothing warned.
- **Published numbers change.** Every `_trend_beta1`, `_trend_gr` and
  `_trend_increasing_pr` a caller was producing under the old default is
  different now, and the trend columns are no longer reproducible run to run
  without a seed. Set one if you need that.
- **`$draws[["<measure>_trend_beta1"]]` is no longer the point estimate.** It
  holds the perturbed draws. Call `rolling_slope_matrix()` for the unperturbed
  slope, its standard error and its convergence flag.
- Passing `propagate_slope_error` now raises an error naming the removal. The
  method takes `...`, so without that guard a caller who had turned it off
  would get propagated numbers and no notice.
- **`family = "identity"` and `family = "quasipoisson"` now refuse
  `trend_isoyearweeks = 2`.** Both read a dispersion off `width - 2` residual
  degrees of freedom, so `se` has no value at width 2 and no `error_reference`
  repairs it. `family = "binomial"` fixes the dispersion at 1 and still accepts
  width 2.
- `n_sim` moved from argument 5 to argument 4, which changes the meaning of a
  positional call.
- `error_reference` is unchanged and still selects the reference distribution.

The `csfmt_rts_data_v1` method is untouched. It fits its own GLM per window and
never had this argument.

## Version

- r-universe publishes 2026.8.26 from commit `576b9c51`, so this tree needs a
  number above it. 2026.8.27 is the release date of this tree.

# Version 2026.8.26

## Trend on the link scale

- **`short_term_trend()` on a `csfmt_ensemble_v3` takes `family`.**
  `"quasipoisson"` is a log link and `"binomial"` is a logit link. `beta1` is
  then the slope on the link scale. That is the `coef(model)[2]` the older
  `glm()` pipelines report, so the two become comparable. `"identity"` is the
  default and reproduces the previous numbers exactly.
- The growth rate on a link scale is `100 * (exp(beta1) - 1)`, a percent change
  per week. Under `"binomial"` that percent change is in the odds.
- A zero count needs no offset. The log link models `E[Y] = exp(b0 + b1 t)` and
  never takes `log(Y)`.
- `family = "binomial"` needs the new `denominator` argument, which names the
  `$draws` measure holding the binomial denominator. It enters the fit as the
  prior weight, and `measure` MUST then be a proportion between 0 and 1.
- The rolling GLM stays a filter. IRLS advances every window of every draw
  together, and no window reaches `stats::glm()`.

## A window that cannot converge returns NA

- **A separated window has no finite slope, and the fit cannot converge.**
  Complete or quasi-complete separation drives the IRLS slope to infinity. The
  iterate that `maxit` stops on is finite, so `is.finite()` never removed it. A
  window of `c(0, 0, 0, 0, 0.2, 0.3, 0.4, 0.5)` separates at width 4, with a
  denominator of 50. Its growth rate reached `$draws` as 1.06e13 percent per
  week. `beta1`, `se` and the growth rate are now `NA_real_` there.
- `rolling_slope_matrix()` returns a fourth matrix, `converged`. It is logical,
  and `NA` on the leading `width-1` rows that hold no window.
- `beta0` is `NA_real_` there too. A lone intercept beside a missing slope reads
  as a fitted level, and it is the same meaningless iterate.
- **An all-zero window returns `NA`, and `stats::glm()` returns a slope of 0.**
  That is the one place the two disagree on purpose. `stats::glm()` stops on the
  relative change in the deviance, which is 0 for an all-zero window from the
  first iteration. This kernel stops on the coefficient step, and that step
  never settles: the intercept marches to `-Inf` as the fitted mean goes to 0.
  An all-zero window identifies no slope, and `NA` says so.
- The warning reports the iteration the batch stopped on, and names `maxit`
  separately. It claimed `maxit` iterations before. A batch holding a
  missing-value window can settle earlier, because the stopping rule drops that
  window with `na.rm`.
- The two GLM families warn once per call, with the count of window fits that
  did not converge. A run of zero weeks followed by a rise is ordinary
  early-season surveillance data, so the warning will fire.

## The slope-error reference is now an argument

- **`short_term_trend()` on a `csfmt_ensemble_v3` takes `error_reference`.**
  `"auto"` is the default. It gives `"identity"` and `"quasipoisson"` a t on
  `trend_isoyearweeks - 2` degrees of freedom. Both estimate a dispersion from
  that many residual degrees of freedom. That is the case `summary.glm()`
  refers to a t.
- `"binomial"` keeps a standard normal under `"auto"`, because that family
  fixes the dispersion at 1 and leaves nothing to estimate.
- Pass `error_reference = "normal"` to match a pipeline whose interval comes
  from `stats::confint()`, which profiles the deviance against an asymptotic
  chi-squared. `"t"` forces the other direction on every family.
- `propagate_slope_error = TRUE` now needs `trend_isoyearweeks >= 3` under
  `family = "identity"` and `family = "quasipoisson"`, whatever the
  `error_reference`. Both read a dispersion off `width - 2` residual degrees of
  freedom, so at width 2 `se` is `NaN` under identity and `Inf` under
  quasi-Poisson. The growth rate then reached `$draws` missing, or as a random
  -100 percent. `family = "binomial"` fixes the dispersion at 1 and still
  accepts width 2.
- `family = "identity"` is unchanged. It drew `se * t_(width-2)` before and it
  still does.

## Static checks

- **`R/` passes the shared `static-checks` gate.** The gate arrived with the
  workflow pin two releases ago and reported 127 findings across 23 of the 24
  code files. Every one is now fixed.
- Every `stop()` and `warning()` names `call. = FALSE`, because the message
  goes to a user who cannot act on the call. Every function returns explicitly.
  `seq_len()` and `seq_along()` replace `1:n`, `&&` and `||` replace `&` and
  `|` inside a condition, and `TRUE` and `FALSE` replace `T` and `F`.
- Seven functions were over 15 cyclomatic complexity and gave their branches to
  named helpers. In `short_term_trend_ensemble.R`, `rolling_irls_slope()` gave
  up `irls_check_response()`, `irls_working()` and `irls_wald_se()`, and
  `short_term_trend.csfmt_ensemble_v3()` gave up `stt_prior_weights()` and
  `stt_error_reference()`.
- No behaviour changes. One user-facing message reads "0.05, 0.25, 0.5, 0.75
  and 0.95" where it read "0.05/0.25/0.5/0.75/0.95", because the slashes read
  as a file path.

## Version

- r-universe published 2026.8.23 from commit `ed0749b8`, so this tree cannot
  reuse that number. 2026.8.26 is the release date of this tree.

# Version 2026.8.23

- The 51-name `utils::globalVariables()` list is gone. Each NSE column name is
  now declared as `NULL` at the top of the one function that uses it: 18
  declarations across 12 files. Only `.` stays package-wide, because it is read
  as an undefined *function* and no local binding fixes that.
- The old list was both too wide and too narrow. `level`, `method`, `period`,
  `role` and `truth` are also formal arguments of other functions, so declaring
  them package-wide suppressed the note for a genuine undefined variable
  anywhere in the package. `coverage_raw` and `horizon` were declared and used
  nowhere.
- `R/csfmt_ensemble.R` already used this idiom at `set_time_series_id()`. The
  package now uses it everywhere.

# Version 2026.8.22

- The package drops `magrittr`. Every `%>%` is now the base pipe `|>`, and
  `magrittr` is gone from `DESCRIPTION`.
- The rewrite is a relocation, not an edit. Each `%>%` call was transformed the
  way R's parser transforms `|>`, and the resulting tree was required to match
  the tree parsed from the rewritten file. A file whose trees disagreed was left
  untouched and converted by hand instead.

- The version runs one day ahead of the calendar on purpose. r-universe already
  published today's number from a different commit, and one version must never
  name two trees.

# Version 2026.8.21

- `R/globals.R` declares `"."`. `R CMD check` read data.table's `.()`, its alias
  for `list()`, as an undefined function rather than an undefined variable, so
  the file's existing declarations did not cover it.

# Version 2026.8.7

## Licensing

* The copyright holder is now **Folkehelseinstituttet**. It read "Core Surveillance", which
  names the package family rather than a legal entity.
* `DESCRIPTION` `Authors@R` now declares that holder with `role = "cph"`.
  It declared no copyright holder at all, and neither did any other package
  in the fleet. Nothing in `R CMD check` reports that.
* The copyright year is now 2026. It read 2023.
* `CLAUDE.md` now carries a Licensing section, so the year gets checked
  rather than silently ageing.

## Corrections

* **`?nowcast_evaluate_v1` claimed common random numbers, and the code does not
  establish them.** Every method starts from the same RNG state on each as-of
  week, which pairs the comparison. Common random numbers would also need the
  methods to consume compatible variates, and nothing enforces that. The
  documentation now states the mechanism and stops there.
  `vignette("pipeline")` already said this. The roxygen contradicted it in
  three places, including a worked example.

## Documentation

* **Every prose file in the repository is swept to ASD-STE100 (Simplified
  Technical English).** The sweep covers the roxygen blocks in `R/`, both
  vignettes, `README.md`, `index.md` and this file. The sweep changed no claim,
  number, hedge or scope qualifier, and no executable line. The one claim that
  did change is under Corrections above.
* **Sentences over 25 words: 34 to 0 in roxygen, 80 to 0 in the vignettes.**
  Counted per authored unit, outside fenced code and outside code-bearing
  roxygen tags. `README.md` went 3 to 0, `index.md` went 1 to 0, and this file
  went 45 to 0. Long sentences were split, not shortened, so every condition
  that made one true survives in the sentences that replaced it.
* `SHOULD` and `SHOULD NOT` are now capitalised in the five places that state an
  obligation. Three are in `R/` and two are in `vignette("pipeline")`. A
  lowercase "should" reads as advice and gets treated as optional.
* **The deprecation notes are unchanged in substance.** They are on
  `?short_term_trend` and `?signal_detection_hlm`. Both still say the
  replacement is not a drop-in, that migration is a rewrite of the call site,
  and that the numbers will not match.
* One roxygen section gained a bulleted list, where three parallel conditions
  were buried in a single sentence. It is the "What it does NOT check" section
  on `?validate_ensemble`. The three conditions are unchanged.
* 31 `@param` descriptions gained the terminal full stop they were missing. No
  wording changed. Without it a sentence counter runs straight through the
  boundary between one field and the next, and reports one very long sentence.


* **New `vignette("csalert")`, the get-started page.** It is an orientation and
  runs no analysis. It covers what the package is for, which of the two
  generations is current, where the `csfmt_rts_data_*` classes live, and what
  cannot be done yet. pkgdown promotes a vignette named after the package to "Get started" in
  the navbar, which is where the site's primary call to action now points.
* **`vignette("nowcasting")` is now `vignette("pipeline")`**, retitled to "The
  pipeline: from incomplete counts to published numbers". Its content, numbers
  and statistical claims are unchanged; the opening paragraphs were rewritten in
  plainer language. The 23 `@seealso` cross-references in `R/` were updated with
  it, so no help page points at a vignette that no longer exists.
* **`vignette("short_term_trend")` is deleted.** It taught
  `short_term_trend.csfmt_rts_data_v1`, which is deprecated, so it was teaching
  new readers the route they should not take. The only worked example of that
  method is now the one on `?short_term_trend`. Its county-map demonstration was
  not ported.

## No behaviour change

* This release changes prose only. No exported function, argument, default or
  return value moved.

## Bug fix

* **`qc_week_over_week_v1()` silently dropped every HLM alert transition.**
  `signal_detection_hlm()` writes naming-grammar role `"hlmstatus"`, but the
  function selected only `role == "status"` for its `$signal` table. An
  escalation from normal to high therefore never appeared in the week-over-week
  review.
  Demonstrated on a 380-week series: a real transition from 1 to 2 at week
  2025-14 returned 0 rows before the fix and 1 after. HLM needs roughly five
  years of history before it produces a status at all, which is why a shorter
  test series shows nothing.
* The same filter had a second, opposite half. `$integrity` excluded
  `role != "status"`, so HLM status CODES were diffed as if they were continuous
  medians. An ordinal 1-to-2 step read as a numeric revision.
* Both halves are now driven by a new `status_roles` argument, which defaults to
  `c("status", "hlmstatus")`. The roles excluded from `$integrity` are exactly
  the roles whose transitions appear in `$signal`. Pass a different vector to
  narrow or widen it.
* **This changes no legacy path.** `qc_week_over_week_v1()` operates on collapsed
  ensemble output. Its only callers are this package's tests and the
  ensemble-first pipelines. Nothing on the pre-ensemble `csfmt_rts_data_v1` route
  reaches it.

# Version 2026.8.6

## Bug fix

* **`short_term_trend()` on an ensemble broke the data.table's self-reference,
  so the NEXT stage warned.** It added its P(increasing) column with base
  `[[<-`, which copies the table. Any later stage assigning with `:=` then
  emitted data.table's ten-line "shallow copy was taken" advisory. Bisected:
  `rate -> hlm` is clean, `rate -> trend -> hlm` warns. That is the canonical
  order, so every production pipeline running a trend before another ensemble
  stage saw it on every run. Now uses `data.table::set()`. Proven causally red:
  reverting the one line reproduces the warning.

## Documentation

* **`vignette("nowcasting")` now runs the whole canonical chain** on one
  synthetic triangle with a denominator. The stages are nowcast, replay
  validation, reporting completion, rate, short-term trend, MEM intensity, HLM
  signal detection, and the terminal collapse. It opens by stating the rule the
  architecture turns on. Every analytical stage takes a `csfmt_ensemble_v3` and
  returns one, and `ens_collapse()` is terminal. A collapsed table is therefore
  output and never input.
  `ens_add_rate()`, `mem_thresholds_v1()` and `signal_detection_hlm()` were
  previously named in prose but never run; production depends on all three.

## Deprecated

* **`short_term_trend.csfmt_rts_data_v1()` and
  `signal_detection_hlm.csfmt_rts_data_v1()` are deprecated.** They are the
  pre-ensemble architecture. Both still work and NEITHER WARNS AT RUN TIME, so
  existing pipelines are undisturbed; the mark is a signpost for new work.
* The replacement is not a drop-in. The v1 methods take `numerator`,
  `denominator`, `prX` and the naming-prefix arguments, and return a status
  label. The ensemble methods take one `measure` and return a per-draw slope,
  growth rate and P(increasing), with no classification. Migrating is a rewrite
  of the call site and the numbers will not match.
* `short_term_trend()` and `signal_detection_hlm()` now have
  `csfmt_rts_data_v3` methods that only `stop()`, naming the architecture
  instead of failing with a bare `UseMethod` error. A collapsed table carries
  quantiles, not draws, so a per-draw trend cannot be recovered from one.

# Version 2026.8.5

## Bug fix

* **`reporting_completion_v1(triangle, max_delay = 1)` returned nonsense,
  silently.** With a single delay column `apply(M, 1, cumsum)` returns a vector
  rather than a matrix. The transpose then produced a 1-by-n_settled matrix. The
  function emitted one `pct_delay` column PER SETTLED WEEK instead of one in
  total, with `complete_by_md` far below 1. Measured on a 30-week triangle: 30
  completion columns and `complete_by_md` of 0.033, where both should be 1. No
  error was raised. Fixed, with a regression test that also pins the column count
  to `max_delay` at horizons 1 through 4.

## Documentation

* **`vignette("nowcasting")` is now a four-stage end-to-end pipeline** on one
  seeded synthetic triangle: nowcast, replay validation, reporting completion,
  short-term trend. Every chunk executes under `R CMD check`. The
  reporting-completion section answers the question the old text left open: is
  the first completion column the reference week or the week after? It walks a
  named ISO week day by day. It shows that delay is measured in whole ISO weeks,
  so a Monday run and a Friday run bucket every report identically.
* **`nowcast_truth()`'s description was off by one, in both bounds.** It said it
  summed "all delays up to `max_delay`" and kept weeks "at least `max_delay`
  weeks before" the as-of. The code sums delays `0 .. max_delay - 1` and keeps
  `age >= max_delay - 1`. Measured: at `max_delay = 3` the newest settled
  reference week is 2 weeks before as-of, not 3. Corrected.

## Breaking change

* **`reporting_completion_v1()` renames its completion columns from `pct_wN` to
  `pct_delayD`, and they are now 0-based and indexed by DELAY**. With
  `max_delay = 3` the columns were `pct_w1`, `pct_w2`, `pct_w3`; they are now
  `pct_delay0`, `pct_delay1`, `pct_delay2`.
* The old names were indexed by weeks-observed, counting the reference week
  itself as week 1, so `pct_w1` held delay 0. The number in the name never
  equalled the delay it represented. Next to a reporting triangle whose
  columns are delays 0, 1, 2, it read as "the week after". `pct_delay0` says
  outright that it is the reference week itself.
* The new names match the `max_delay` argument: the column count equals
  `max_delay` and the highest index is `max_delay - 1`.
* **Update any code that reads these columns.** The old names are gone rather
  than redefined, so stale code fails with an unknown-column error instead of
  silently returning a different week. `reporting_completion_trend_v1()` passes
  the columns through and changes with it.

# Version 2026.8.4

## Documentation

- **Every exported function now has a runnable example.** 21 of the 34 exports had
  none; they already had a title, a description, `@param` and `@returns`, but
  nothing a reader could run. The new examples all execute under `R CMD check`.
  None is wrapped in `\dontrun{}` or `\donttest{}`, because nothing in the package
  needs a live database, a credential or a mounted share to demonstrate. The
  nowcast pipeline examples share one 40-week synthetic reporting triangle,
  right-truncated so the newest weeks are genuinely incomplete.
- **Every exported function now carries an `@seealso` that says which vignette
  covers it, including when the honest answer is "neither".** Only eight exports
  are actually run inside a vignette code chunk. `ens_add_rate()`,
  `mem_thresholds_v1()` and
  `signal_detection_hlm()` are named in the closing "Where next" list of the
  nowcasting vignette, but not demonstrated there. The `@seealso` now says so
  rather than implying coverage.
- **Eight `@family` groups added as topical navigation**, so the reference pages
  cross-link. The groups are ensemble format functions, reporting triangle
  functions, naming grammar functions, nowcast engines, nowcast diagnostics,
  nowcast calibration functions, ensemble operations, and reporting completion
  functions. These group
  functions by the concept they belong to, not by a shared call signature. Only
  `nowcast engines` is a set of interchangeable implementations. The other seven
  are pipeline stages or helpers around one concept, and each member's `@seealso`
  states its own specific role. The two `qc_*` functions were deliberately *not*
  made a family. `qc_surveillance_data_v1()` screens one input feed and returns a
  verdict. `qc_week_over_week_v1()` diffs two finished runs and returns two
  tables. They are cross-linked with `@seealso` instead.
- **`compare_results()` gained an "Identity columns" section.** It finds its value
  columns with `csfmt_interpret()`. An identity column outside the csfmt
  structural schema — `location` rather than `location_code` — is therefore read
  as a value column. `cur`/`prv` then come back as character instead of numeric.
  `qc_week_over_week_v1()` then fails outright with
  `Error in cur - prv : non-numeric argument to binary operator`. The nowcasting
  vignette teaches exactly those non-schema names, so this is easy to hit.
- **README grown from 23 words to a landing page**. It covers what the package
  is, the two routes through it, installation, one quick start, a
  which-function-do-I-want table, and links to the pkgdown site. It copies no
  passage from either vignette; the longest shared run of consecutive words is
  three. It does necessarily summarise the same pipeline the nowcasting vignette
  explains in full.

## Corrected statistical documentation

No behaviour changed. Each of these help pages described a model, or a guarantee,
that the code does not implement. An adversarial review found them.

- **`nowcast_quasipoisson_v1()` is not fitted without an intercept.** The
  documentation said "no intercept" in two places. But the formula is built as
  `y ~ d1 + d2 + ...`, which carries R's default intercept. An inline comment in
  the source already said `# + intercept`. The documented model now matches the
  fitted one.
- **"Honestly dispersed" removed from the same engine.** Simulating from a fitted
  model and truncating at the observed count does not establish calibrated
  coverage. The documentation now says calibration is an empirical question about
  a given series and points at `nowcast_evaluate_v1()`, which exists to measure it.
- **The calibration functions no longer claim split conformal or nominal
  coverage.** The estimator takes the ordinary type-7 quantile of
  `|truth - median| / halfwidth`, not the conformal order statistic. That
  symmetric residual is only faithful for intervals roughly symmetric about the
  median. There is no finite-sample guarantee. `coverage_raw` is now documented as
  what the engine did on the replayed weeks, not as a property of the engine.
- **`complete_by_md` is documented as identically 1.** It was described as
  detecting reporting that continues past the horizon. It cannot:
  `reporting_triangle_matrix()` discards delays at or beyond `max_delay` before
  the total is formed. The final cumulative fraction of that truncated total is
  therefore always 1, and `pct_delay<max_delay-1>` is always 100. To look for a tail, re-run with a
  larger `max_delay`. **This is a source defect left unfixed and now documented.**
- **`q_value()` is no longer described as the inverse of `q_label()`.** The label
  format holds two integer-percent digits, so `q_label(1)` gives `"q100x0"`, which
  `q_value()` returns `NA` for. The round trip holds on `[0, 1)`.
- **`csfmt_parse()` is no longer described as the inverse of `csfmt_var()`.** It
  strips a role from the right against a fixed vocabulary. On the package's own
  rate name `numerator_nowcasted_vs_denominator_nowcasted_pr100` it eats the
  denominator's `_nowcasted` as the role, and returns `denom = "denominator"`. A
  new section documents the limit with that exact name.
- **`validate_ensemble()` is retitled "Check a csfmt_ensemble_v3's structural
  shape".** It checks class, two column names, and that each draw matrix has one
  row per row of `$data` — the row COUNT only. Permuting the rows of `$data` or of
  a draw matrix passes, as do a missing key, a broken `time_series_internal_id`
  and a deleted `time_series_label`. The page previously implied it was a safety
  net for hand-edited objects. It now says to rebuild with `csfmt_ensemble_v3()`
  instead, and its example demonstrates a permutation passing.
- **`qc_week_over_week_v1()` cannot see HLM transitions.** `signal_detection_hlm()`
  writes role `"hlmstatus"` while the check selects role `"status"`, so only
  `mem_thresholds_v1()` output reaches `qc$signal`. The example said otherwise and
  now records the gap.

## Packaging

- `^pkgdown$` and `^Rplots\.pdf$` added to `.Rbuildignore`. `pkgdown::build_site()`
  leaves a `pkgdown/favicon/` directory behind, and an example that draws a plot
  leaves an `Rplots.pdf`. Both otherwise ship in the tarball and raise a
  non-standard-top-level-file NOTE.

# Version 2026.7.1

## Trend uncertainty

- **`short_term_trend()` can now propagate the slope's own sampling error.**
  The growth rate is `100 * beta1 / Y`. Until now only the uncertainty of
  the level `Y` reached it, and the OLS standard error of `beta1` was computed
  and discarded. So every trend interval reflected nowcast uncertainty alone. A
  passthrough (single-draw) series got a zero-width interval and a
  `P(increasing)` of exactly 0 or 1. That is a bare sign test on a three-point
  slope presented as certainty.
  `propagate_slope_error = TRUE` adds `se * t_(width-2)` per draw, widening the
  trend's own draw axis to `n_sim` when the incoming ensemble is degenerate.
  Defaults to `FALSE`, so published numbers are unchanged until it is switched
  on deliberately. Note the degrees of freedom are `trend_isoyearweeks - 2`: at
  the default window of 3 that is a Cauchy, so widen the window first.

## Nowcast calibration, restored as a diagnostic

- **`nowcast_estimate_calibration_v1()` / `nowcast_apply_calibration_v1()` are
  back**, after being removed earlier in this release cycle. They are available
  to *check an engine with*, not applied to published numbers. The estimator
  reports a per-horizon `factor`. So "your 90% interval would need to be 1.4x
  wider to actually cover 90%" is readable straight off the backtest. That is a
  far more actionable red flag than a bare coverage fraction, and it keeps the
  published number the model's own.
- Their tests now run against `nowcast_quasipoisson_v1`. The old assertions
  (`factor > 1` everywhere, raw coverage below 0.82) encoded the removed
  `nowcast_survrtrunc_v1`'s behaviour. The current engine covers about 0.87 on
  the same drifting-delay synthetic, close enough to nominal that no widening is
  warranted.

## Bug fixes

- `prediction_interval.glm` is now registered with `S3method()`. It resolved
  when the package was installed, but not under `devtools::load_all()`. The
  method's own test therefore failed in a dev tree while passing in
  `R CMD check`.

## Simplification

- **`reporting_completion_trend_v1`** returns the completion curve by calendar year
  (all) + by month (last N, per series), with a `scope` column. That is the
  year/month trend the luftveis pipeline used to assemble by hand.
- **`nowcast_evaluate_v1`** is now the single entry point for scoring nowcasts.
  Give it a triangle and one method, or a NAMED list. It replays each --
  paired by a shared `seed` -- and returns one per-horizon table of interval
  coverage + point-estimate revision, with a `method` column. It subsumes the
  former `nowcast_score` (coverage, via scoringutils), `nowcast_revision`,
  `nowcast_compare` and `nowcast_validate`. Coverage is read straight off the
  interval quantiles, so **`scoringutils` is no longer a dependency** (WIS was
  dropped).
- Removed the unused **`nowcast_survrtrunc_v1`** engine, and its `flexsurv`
  dependency. Also removed the conformal **calibration** functions
  (`nowcast_estimate_calibration_v1` / `_apply_` / `print.nowcast_calibration`).
  Both were already dropped from the production pipeline.
- Renamed `mem_thresholds` -> **`mem_thresholds_v1`** (versioned-engine convention).

## Documentation

- New vignette **"Nowcasting a reporting triangle with csfmt_ensemble_v3"** — a
  runnable end-to-end walk-through (synthetic triangle -> nowcast -> collapse ->
  backtest coverage/revision/completion -> naming grammar).
- Documented the previously-bare `print.csfmt_ensemble_v3` method; added the
  missing `@returns` to the ensemble/nowcast S3 methods (`mem_thresholds_v1`,
  `short_term_trend`, `signal_detection_hlm`, `nowcast_quasipoisson_v1`).
- Added runnable `@examples` to the naming-grammar functions (`csfmt_var`,
  `csfmt_parse`, `q_label`, `q_value`) and to the nowcast analysis functions
  (`nowcast_evaluate_v1`, `reporting_completion_trend_v1`).
- Fixed unescaped `%` in the nowcast / `reporting_completion` roxygen that had
  been corrupting their generated `.Rd`, plus copy-paste errors in the
  simulation-helper docs.

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
  seasons. `exclude_seasons` drops anomalous seasons from the baseline. Training
  is capped to the most recent `i.seasons` before `na.omit`. A non-zero-season
  guard plus a quiet `memmodel` wrapper prevent sparse indicators from erroring.
- `signal_detection_hlm.csfmt_ensemble_v3`: per-draw exceedance detection.
- `add_holiday_effect` for the ensemble format.
- Input QC: `qc_surveillance_data` (generic input QC, verdict only) and
  `qc_week_over_week` (A/B revision comparison across runs).
- `add_rate` and `collapse` are renamed to `ens_add_rate` / `ens_collapse`.
  They are now S3 generics dispatching on `csfmt_ensemble_v3` (the `ens_`
  family), so the ensemble class carries the "operates on an ensemble" meaning.
  Behaviour is unchanged. (`add_holiday_effect` is a simulation-data helper on a
  plain data.table and keeps its name).
- `nowcast` and `observed_ensemble` are renamed to `nowcast_survrtrunc_v1` and
  `nowcast_passthrough_to_ensemble_v1` -- concrete, VERSIONED nowcast engines that
  share the contract `f(reporting_triangle, ...) -> csfmt_ensemble_v3`. Behaviour
  is unchanged; the `_vN` suffix versions the algorithm (a future `nowcast_stan_v1`
  or `nowcast_simple_v2` slots in beside them), selected by a caller-side registry.
  The validation harness (nowcast_backtest/score/compare/validate/censor/truth) is
  generic tooling and is NOT versioned.
- `nowcast_survrtrunc_v1` gains `delay_window` (default 26 weeks): the reporting-delay
  distribution is estimated from only the most recent weeks, so a non-stationary /
  drifting delay (e.g. a backfilled history then live prospective reporting) is
  tracked instead of averaged into a stale pooled curve. Fixes the median bias
  that caused sub-nominal interval coverage. Residual under-coverage (plug-in delay)
  is documented by the calibration test, and awaits per-draw delay uncertainty or
  backtest-driven recalibration. `NULL` restores the old pool-all-history behaviour.
- Calibration test (`test-nowcast-calibration.R`): empirical interval coverage vs
  nominal on synthetic data, with a stationary case (calibrated) and a
  drifting-delay case (reproduces the real-data under-coverage synthetically).
- `nowcast_simple_v1` renamed to `nowcast_survrtrunc_v1` (the name now states the
  method: right-truncated survival delay + negbin completion).
- New engine `nowcast_quasipoisson_v1`: a discriminative (regression) nowcast.
  For each horizon, regress the settled TOTAL on the counts reported so far, on
  the recent settled weeks. The regression is
  `total ~ n[delay 0] + n[delay 1] + ...`, quasipoisson/identity, no intercept.
  Then simulate the incomplete weeks (parameter
  uncertainty from the fit + a dispersion-matched negbin). No per-week magnitude
  parameter, so it is robust for the recent weeks and honestly dispersed.
  Drifting-delay synthetic coverage is ~0.79, vs the plug-in survrtrunc's ~0.72
  (nominal 0.90). Base stats only; same `f(triangle) -> ensemble` contract ->
  drops into the registry as a candidate key.
- Backtest-driven recalibration. `nowcast_estimate_calibration_v1` learns a
  per-group (default horizon) conformal interval-scaling correction from past
  nowcasts vs settled truth. `nowcast_apply_calibration_v1` applies it, so a
  method's intervals hit nominal coverage regardless of internal misspecification.
  A `nowcast_calibration` S3 object with a print method sits between. Turns the
  backtest into calibration data: engine -> backtest -> estimate -> apply ->
  honest intervals. Distribution-free (split conformal); estimate on past
  backtests, apply to the current nowcast.
- Nowcast validation harness (method-agnostic, replay-based). `nowcast_censor`
  reconstructs what was known as-of a past week from the reporting triangle.
  `nowcast_truth` gives settled totals. `nowcast_backtest` replays any
  `f(triangle) -> ensemble` across as-of weeks into tidy quantile nowcasts.
  `nowcast_evaluate_v1` scores one or several methods on interval coverage +
  point-estimate revision by horizon -- see the Simplification section above.
- `reporting_completion`: the empirical reporting-delay summary of a triangle.
  From the settled weeks it gives the mean delay, and the weeks-observed to reach
  25/50/75/90/95% of a reference week's cases. It also gives the fraction
  actually in by
  `max_delay`. `period = "year"` / `"month"` stratifies the settled weeks in time,
  by the ISO year / midweek-day month. A drift in reporting speed then shows up as
  a trend in mean delay, instead of being averaged away.

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
