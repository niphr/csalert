# The settled (eventually-observed) total per reference week

Sums each reference week's counts across all delays up to \`max_delay\`
– the quantity a nowcast is trying to predict – and keeps only weeks old
enough that this total is settled (at least \`max_delay\` weeks before
the triangle's as-of).

## Usage

``` r
nowcast_truth(triangle, max_delay)
```

## Arguments

- triangle:

  A \`csfmt_reporting_triangle_v3\` (single series).

- max_delay:

  Delay horizon in weeks.

## Value

A data.table \`reference\`, \`truth\`.

## See also

Neither package vignette covers this function.
[`vignette("nowcasting", package = "csalert")`](https://niphr.github.io/csalert/articles/nowcasting.md)
scores a nowcast against settled truth through
[`nowcast_evaluate_v1`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md),
which calls this function for you.

Other nowcast diagnostics:
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
[`nowcast_censor()`](https://niphr.github.io/csalert/reference/nowcast_censor.md),
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)

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

truth <- nowcast_truth(tri, max_delay = 3)

# the two newest weeks are missing: they are not settled yet, so they have no
# truth to be scored against
tail(truth, 3)
#>    reference truth
#>       <char> <num>
#> 1:   2023-36    44
#> 2:   2023-37    43
#> 3:   2023-38    51
c(reference_weeks = 40L, settled = nrow(truth))
#> reference_weeks         settled 
#>              40              38 
```
