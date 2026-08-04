# Replay a nowcast method across as-of weeks (backtest)

For each \`as_of\` week, censor the triangle to what was known then, run
the method, collapse to quantiles, and collect the nowcast for the
reference weeks at the requested horizons (horizon = weeks between
reference and as-of). An as-of week whose method call errors (e.g. too
little history) is skipped with a warning rather than aborting the
sweep.

## Usage

``` r
nowcast_backtest(
  triangle,
  method,
  as_of_weeks = NULL,
  max_delay,
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

  ISO-week strings to replay. Default: every reference week after a
  \`max_delay\`-week burn-in, replayed as-of itself.

- max_delay:

  Delay horizon (used for the default as-of set and burn-in).

- horizons:

  Integer weeks-back to keep (0 = the as-of week itself).

- probs:

  Quantile probabilities to extract.

- measure:

  Ensemble measure to score; default the numerator's nowcast.

- seed:

  Optional integer base seed. Each as-of is seeded as \`seed +
  week-index\`, so a given cell is reproducible regardless of the as-of
  list order (the nowcast draws for week W depend only on \`seed\` and
  \`W\`).

## Value

A long data.table: \`reference\`, \`as_of\`, \`horizon\`,
\`quantile_level\`, \`predicted\`.

## See also

Neither package vignette covers this function.
[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md)
reaches the same replay through
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
which wraps it and scores the result. Use this function directly when
you want the raw replayed quantiles.

Other nowcast diagnostics:
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md)

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

# a method is f(triangle) -> ensemble, with its own parameters baked in
method <- function(x) nowcast_quasipoisson_v1(x, max_delay = 3, n_sim = 200)

# Replay 19 as-of weeks. This window is a runtime choice, not a fitting
# boundary: the engine needs only three settled training rows, and with fewer
# it returns the observed totals rather than failing. Leaving `as_of_weeks`
# NULL replays every week after the burn-in, which is slower.
bt <- nowcast_backtest(
  tri, method,
  max_delay = 3,
  as_of_weeks = w[i + 20:38],
  horizons = 0:1,
  probs = c(0.05, 0.5, 0.95),
  seed = 1
)
head(bt, 6)
#>    reference   as_of horizon quantile_level predicted
#>       <char>  <char>   <int>          <num>     <num>
#> 1:   2023-20 2023-21       1           0.05      38.0
#> 2:   2023-21 2023-21       0           0.05      38.0
#> 3:   2023-20 2023-21       1           0.50      44.0
#> 4:   2023-21 2023-21       0           0.50      47.5
#> 5:   2023-20 2023-21       1           0.95      54.1
#> 6:   2023-21 2023-21       0           0.95      61.0
```
