# Replay a nowcast method on past as-of dates

For each as-of date, cuts the triangle back with
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
runs the method and collapses the result to quantiles. When the method
fails on a date, the function warns and goes on.

## Usage

``` r
nowcast_backtest(
  triangle,
  method,
  as_of_weeks = NULL,
  max_delay_days,
  horizons = 1:2,
  probs = c(0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.975),
  measure = NULL,
  seed = NULL
)
```

## Arguments

- triangle:

  A `csfmt_reporting_triangle_v3` with one series.

- method:

  A function that takes a triangle and returns a `csfmt_ensemble_v3`,
  with its other arguments fixed.

- as_of_weeks:

  A `Date` vector of as-of dates. `NULL` uses the last day of each
  reference week after a burn-in of `max_delay_days`, rounded up to
  whole weeks. That range covers the weeks with a report at delay day 0
  to `max_delay_days - 1`. With no such week, the result is empty.

- max_delay_days:

  The delay horizon in days. It sets the default as-of dates and the
  burn-in.

- horizons:

  The horizons to keep, in weeks.

- probs:

  The probabilities of the quantiles to keep.

- measure:

  The draw matrix to score. `NULL` is `<value_col>_nowcasted`.

- seed:

  A base seed, or `NULL`. The seed for a date is
  `seed + as.integer(as_of)`, so its draws do not depend on the order of
  the dates.

## Value

A long data.table with `reference`, `as_of`, a `Date`, `horizon`,
`quantile_level` and `predicted`.

## Details

The horizon of a reference week is the number of whole weeks from its
Monday to the as-of date. Horizon 0 is the week of the as-of date.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2.
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
runs this function and scores the result.

Other nowcast diagnostics:
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

## Examples

``` r
monday <- as.Date("2023-01-02") + 7 * rep(0:39, each = 3)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = format(monday, "%G-%V"),
  reporting_date = monday + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= as.Date("2023-01-02") + 7 * 39 + 6]
tri <- csfmt_reporting_triangle_v3(
  d,
  id_cols = c("indicator_tag", "location_code", "age", "sex")
)

# a method takes a triangle and returns an ensemble
method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)

# Replay 19 as-of dates, each the Sunday that ends a reference week. Fewer
# dates only save time: with fewer than 3 settled weeks the engine returns
# the observed totals and does not fail. `as_of_weeks = NULL` replays every
# week after the burn-in.
bt <- nowcast_backtest(
  tri, method,
  max_delay_days = 21,
  as_of_weeks = as.Date("2023-01-02") + 7 * (20:38) + 6,
  horizons = 0:1,
  probs = c(0.05, 0.5, 0.95),
  seed = 1
)
head(bt, 6)
#>    reference      as_of horizon quantile_level predicted
#>       <char>     <Date>   <int>          <num>     <num>
#> 1:   2023-20 2023-05-28       1           0.05  39.88012
#> 2:   2023-21 2023-05-28       0           0.05  39.42942
#> 3:   2023-20 2023-05-28       1           0.50  42.13826
#> 4:   2023-21 2023-05-28       0           0.50  47.12500
#> 5:   2023-20 2023-05-28       1           0.95  44.85250
#> 6:   2023-21 2023-05-28       0           0.95  56.13357
```
