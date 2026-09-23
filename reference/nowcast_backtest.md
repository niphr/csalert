# Replay a nowcast method across as-of dates (backtest)

For each \`as_of\` date, censor the triangle to what was known then, run
the method, collapse to quantiles, and collect the nowcast for the
reference weeks at the requested horizons (horizon = whole weeks between
the reference week and the as-of date). An as-of date whose method call
errors (e.g. too little history) is skipped with a warning rather than
aborting the sweep.

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

  A \`csfmt_reporting_triangle_v3\` (single series).

- method:

  A function \`f(triangle) -\> csfmt_ensemble_v3\` (params baked in).

- as_of_weeks:

  A \`Date\` vector of as-of dates to replay. Default: the last day of
  each reference week, after a burn-in of \`max_delay_days\` rounded up
  to whole weeks. The weeks run from the first to the last week with a
  report at delay day 0 to \`max_delay_days - 1\`. A week whose only
  reports are later does not extend that range. The name says weeks
  because the replay cadence is weekly. The values are dates.

- max_delay_days:

  Delay horizon in DAYS. Sets the default as-of set and the burn-in.

- horizons:

  Integer weeks-back to keep (0 = the as-of week itself).

- probs:

  Quantile probabilities to extract.

- measure:

  Ensemble measure to score; default the numerator's nowcast.

- seed:

  Optional integer base seed. Each as-of is seeded as \`seed +
  as.integer(as_of)\`, the as-of date's day number, so a given cell is
  reproducible regardless of the as-of list order. The nowcast draws for
  date D depend only on \`seed\` and \`D\`.

## Value

A long data.table: \`reference\`, \`as_of\`, \`horizon\`,
\`quantile_level\`, \`predicted\`. \`as_of\` is a \`Date\`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
runs this function in its validation stage.
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
wraps it and scores the result; use this one directly when you want the
raw replayed quantiles.

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

# a method is f(triangle) -> ensemble, with its own parameters baked in
method <- function(x) nowcast_delay_ecdf_v1(x, max_delay_days = 21, n_sim = 200)

# Replay 19 as-of dates, each the Sunday that ends a reference week. This
# window is a runtime choice, not a fitting boundary: the engine needs only
# three settled training rows, and with fewer it returns the observed totals
# rather than failing. Leaving `as_of_weeks` NULL replays every week after the
# burn-in, which is slower.
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
