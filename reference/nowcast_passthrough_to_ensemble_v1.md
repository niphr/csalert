# Build an ensemble from a reporting triangle WITHOUT nowcasting (passthrough)

Collapse the triangle to the observed (reported-so-far) totals per
reference week and wrap them as a degenerate single-draw ensemble. Some
indicators SHOULD NOT be nowcast-completed, because reporting is
effectively complete or the analyst chose not to model the delay. Such
an indicator then flows through the SAME rate/trend/MEM/collapse
pipeline, with its observed values unchanged. It emits the same
\`\<measure\>\_nowcasted\` columns as the modelling engines, here equal
to the observed value. All downstream code is therefore identical. The
single draw makes every collapsed quantile equal the observed point.

## Usage

``` r
nowcast_passthrough_to_ensemble_v1(x, max_delay, denominator_col = NULL)
```

## Arguments

- x:

  A \`csfmt_reporting_triangle_v3\`.

- max_delay:

  Delay horizon (defines the contiguous reference grid).

- denominator_col:

  Optional denominator column, carried through the same way (its
  observed total is also surfaced as \`\<denom\>\_observed\`).

## Value

A \`csfmt_ensemble_v3\` with single-column draw matrices.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
races this engine against
[`nowcast_quasipoisson_v1`](https://niphr.github.io/csalert/reference/nowcast_quasipoisson_v1.md)
on the same triangle. That is the clearest way to see what completion
buys you over the observed counts passed through unchanged.

Other nowcast engines:
[`nowcast_quasipoisson_v1()`](https://niphr.github.io/csalert/reference/nowcast_quasipoisson_v1.md)

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

ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay = 3)
ens
#> <csfmt_ensemble_v3> 40 rows | 1 series | draws: numerator_nowcasted

# one draw only, so every collapsed quantile equals the observed total --
# including for the newest, still-incomplete weeks
r <- ens_collapse(ens, probs = c(0.05, 0.5, 0.95))
tail(r[, .(
  isoyearweek, original,
  lo = numerator_nowcasted_q05x0,
  med = numerator_nowcasted_q50x0,
  hi = numerator_nowcasted_q95x0
)], 3)
#>    isoyearweek original    lo   med    hi
#>         <char>    <num> <num> <num> <num>
#> 1:     2023-38       51    51    51    51
#> 2:     2023-39       44    44    44    44
#> 3:     2023-40       20    20    20    20
```
