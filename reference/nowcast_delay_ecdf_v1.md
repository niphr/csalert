# Nowcast a reporting triangle into an ensemble (daily delay ECDF)

Completes each incomplete reference week from a pool of settled
reference weeks. Each draw is the count observed so far, times a
quantile of the completion ratios that the pool shows at the same delay
day.

## Usage

``` r
nowcast_delay_ecdf_v1(x, ...)

# S3 method for class 'csfmt_reporting_triangle_v3'
nowcast_delay_ecdf_v1(
  x,
  max_delay_days,
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

- max_delay_days:

  Delay horizon in DAYS: delay day 0 to \`max_delay_days - 1\`.
  \`max_delay_days = 35\` gives the 35 days that start on the reference
  week's Monday. Day \`max_delay_days - 1\` also holds every later
  delay.

- n_sim:

  Number of nowcast draws.

- denominator_col:

  Optional denominator column to nowcast alongside.

- delay_window:

  Build the pool from the settled weeks of roughly this many WEEKS, so
  it tracks a drifting reporting regime. Default 26. \`NULL\` uses every
  settled week. This argument is the one quantity here that is weeks and
  not days.

## Value

A \`csfmt_ensemble_v3\` with one row per reference week, and an
\`n_sim\`-column draw matrix of the nowcasted total per week. Settled
weeks are degenerate at their observed total. Incomplete weeks carry the
empirical completion interval measured on the settled pool. A second
measure is added when \`denominator_col\` is given.

## Details

Take a reference week of age \`d\` days, so delay days 0 to \`d\` are
observed. The pool is the settled reference weeks inside
\`delay_window\`. For pool week \`s\`, \`T_s\` is its settled total and
\`O_s\` is its count by delay day \`d\`. The draws are \`observed_so_far
\* quantile(T_s / O_s)\`, in random order. The quantiles sit at
\`n_sim\` evenly spaced probabilities from 0 to 1, or at 0.5 when
\`n_sim\` is 1. A pool week with \`O_s = 0\` is left out. With fewer
than 3 pool weeks left, the reference week keeps its observed count.

The interval is empirical: the 5 Nothing parametric is added on top,
because the spread of the pool ratios already carries the estimation
error and the reporting noise. A nowcast never falls below the observed
count.

A pool week counts as settled once it is \`max_delay_days - 1\` days
old. That means its correction stops, not that its reporting is
finished: a later report still adds to its last delay column. During a
long reporting backlog that reaches most of the pool, the pool ratios
are then too small and the nowcast runs low.

A pool week with \`O_s = 0\` has no finite ratio, so it cannot enter the
pool. The interval therefore does not describe a week whose reporting
has not started, and a reference week with no observed count stays at 0.

The engine also forms \`p(d)\`, the pooled share of a week's counts that
arrives by delay day \`d\`. \`p(d)\` cancels out of every draw. It only
decides whether delay day \`d\` is completed: when \`p(d)\` is 0, the
reference week keeps its observed count. So the draws are not built from
\`observed_so_far / p(d)\`, the closed-form maximum likelihood estimate
under \`n\[ref, d\] ~ Poisson(lambda\[ref\] \* p\[d\])\`.

There is no weekday term. Every reference week starts on a Monday, so
delay day \`d\` is always the same weekday. The pool ratios at delay day
\`d\` therefore absorb the weekly pattern.

Whether the intervals are calibrated for YOUR series is an empirical
question. Measure it with \[nowcast_evaluate_v1\]. Shares the contract
\`f(reporting_triangle, ...) -\> csfmt_ensemble_v3\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this engine on a synthetic triangle and then scores it.

Other nowcast engines:
[`nowcast_passthrough_to_ensemble_v1()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_to_ensemble_v1.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday, then
# right-truncated so the newest weeks are still incomplete
cal <- cstime::dates_by_isoyearweek
i <- match("2023-01", cal$isoyearweek)
set.seed(1)
monday <- as.Date(cal$mon[i + rep(0:39, each = 3)])
d <- data.table::data.table(
  isoyearweek_reference = cal$isoyearweek[i + rep(0:39, each = 3)],
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date(cal$mon[i + 39]) + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

set.seed(2)
ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = 21, n_sim = 200)
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
#>    isoyearweek original       lo      med       hi
#>         <char>    <num>    <num>    <num>    <num>
#> 1:     2023-37       43 43.00000 43.00000 43.00000
#> 2:     2023-38       51 51.00000 51.00000 51.00000
#> 3:     2023-39       44 47.03571 48.70709 52.73889
#> 4:     2023-40       20 29.67831 34.82676 38.94022
```
