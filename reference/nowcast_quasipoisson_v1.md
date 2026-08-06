# Nowcast a reporting triangle into an ensemble (quasipoisson reporting regression)

A discriminative (regression) nowcast engine. For each horizon it
regresses the settled total on the counts reported so far: \`total ~
n\[delay 0\] + n\[delay 1\] + ...\`. The regression is quasipoisson with
an identity link and R's default intercept. It then completes the
incomplete weeks by simulation from that fit: parameter uncertainty plus
a dispersion-matched negbin. There is no per-week magnitude parameter,
so the recent weeks do not each carry their own noisy level. Whether the
intervals it produces are calibrated for YOUR series is an empirical
question; measure it with \[nowcast_evaluate_v1\]. Shares the contract
\`f(reporting_triangle, ...) -\> csfmt_ensemble_v3\`.

## Usage

``` r
nowcast_quasipoisson_v1(x, ...)

# S3 method for class 'csfmt_reporting_triangle_v3'
nowcast_quasipoisson_v1(
  x,
  max_delay,
  n_sim = 1000,
  denominator_col = NULL,
  delay_window = 26,
  ...
)
```

## Arguments

- x:

  A \`csfmt_reporting_triangle_v3\`.

- ...:

  Passed to methods.

- max_delay:

  Delay horizon in weeks.

- n_sim:

  Number of nowcast draws.

- denominator_col:

  Optional denominator column to nowcast alongside.

- delay_window:

  Train on only settled weeks within roughly this many weeks (tracks a
  drifting regime). Default 26; \`NULL\` uses all settled weeks.

## Value

A \`csfmt_ensemble_v3\` with one row per reference week and an
\`n_sim\`-column draw matrix of the nowcasted total per week. Settled
weeks are degenerate at their observed total; incomplete weeks carry the
regression's parameter + dispersion uncertainty. A second measure is
added when \`denominator_col\` is given.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this engine on a synthetic triangle and then scores it.

Other nowcast engines:
[`nowcast_passthrough_to_ensemble_v1()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_to_ensemble_v1.md)

## Examples

``` r
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 39]]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

set.seed(2)
ens <- nowcast_quasipoisson_v1(tri, max_delay = 3, n_sim = 200)
ens
#> <csfmt_ensemble_v3> 40 rows | 1 series | draws: numerator_nowcasted

# settled weeks sit exactly on their observed total; the newest weeks are
# completed, and carry an interval
r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
tail(r[, .(
  isoyearweek, original,
  lo = numerator_nowcasted_q05x0,
  med = numerator_nowcasted_q50x0,
  hi = numerator_nowcasted_q95x0
)], 4)
#>    isoyearweek original    lo   med    hi
#>         <char>    <num> <num> <num> <num>
#> 1:     2023-37       43    43  43.0 43.00
#> 2:     2023-38       51    51  51.0 51.00
#> 3:     2023-39       44    44  48.0 60.05
#> 4:     2023-40       20    30  40.5 53.00
```
