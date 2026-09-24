# Nowcast a reporting triangle from the delay pattern of settled weeks

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

  The `csfmt_reporting_triangle_v3` to nowcast.

- ...:

  Passed to the method.

- max_delay_days:

  The delay horizon in days, delay day 0 to `max_delay_days - 1`. Day
  `max_delay_days - 1` also holds every later delay.

- n_sim:

  The number of draws.

- denominator_col:

  A denominator column to nowcast on the same draws. Its observed total
  goes to `$data` as `<denominator_col>_observed`.

- delay_window:

  The span, in weeks, of the settled weeks in the pool, so that the pool
  follows a reporting pattern that changes. `NULL` uses every settled
  week.

## Value

A `csfmt_ensemble_v3` with one row per reference week and a draw matrix
`<value_col>_nowcasted` with `n_sim` columns. A settled week has its
observed total in every draw. `$data` holds `original`, the observed
total.

## Details

Take a reference week of age `d` days, so delay days 0 to `d` are
observed. The pool is the settled reference weeks inside `delay_window`.
For pool week `s`, `T_s` is its settled total and `O_s` is its count by
delay day `d`. The draws are `observed_so_far * quantile(T_s / O_s)`, in
random order. The quantiles sit at `n_sim` evenly spaced probabilities
from 0 to 1, or at 0.5 when `n_sim` is 1.

A pool week with `O_s = 0` has no finite ratio, so it cannot enter the
pool. With fewer than 3 pool weeks left, the reference week keeps its
observed count. The interval therefore does not describe a week whose
reporting has not started, and a reference week with no observed count
stays at 0.

The interval is empirical: the 5% and 95% draw quantiles are the band.
Nothing parametric is added, because the spread of the pool ratios
already carries the estimation error and the reporting noise. A nowcast
never falls below the observed count.

A pool week is settled once it is `max_delay_days - 1` days old. Its
correction then stops, but its reporting can continue: a later report
adds to its last delay column. So when a long reporting backlog reaches
most of the pool, the pool ratios are too small and the nowcast runs
low.

The engine also forms `p(d)`, the pooled share of the counts of a week
that arrive by delay day `d`. `p(d)` cancels out of every draw. It only
decides whether delay day `d` is completed: when `p(d)` is 0, the
reference week keeps its observed count. So the draws are not built from
`observed_so_far / p(d)`, the closed-form maximum likelihood estimate
under `n[ref, d] ~ Poisson(lambda[ref] * p[d])`.

There is no weekday term. Every reference week starts on a Monday, so
delay day `d` is always the same weekday. The pool ratios at delay day
`d` therefore absorb the weekly pattern.

Whether the intervals are calibrated for your series is an empirical
question. Measure it with
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md).
Like every nowcast engine, this one takes a reporting triangle and
returns a `csfmt_ensemble_v3`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this engine on a synthetic triangle and scores it.

Other nowcast engines:
[`nowcast_passthrough_to_ensemble_v1()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_to_ensemble_v1.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday. The
# data stops at one as-of date, so the newest weeks are still incomplete.
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

# a settled week sits on its observed total, and a newest week is completed
# with an interval
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
