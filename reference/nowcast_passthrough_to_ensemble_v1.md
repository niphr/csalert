# Build an ensemble from a reporting triangle with no nowcast

Returns the counts reported so far as an ensemble with one draw. Use it
for an indicator that SHOULD NOT be nowcast, and the rest of the
pipeline runs unchanged.

## Usage

``` r
nowcast_passthrough_to_ensemble_v1(x, max_delay_days, denominator_col = NULL)
```

## Arguments

- x:

  The `csfmt_reporting_triangle_v3` to pass through.

- max_delay_days:

  The delay horizon in days. The totals do not depend on it, because a
  later report counts in the last delay column.

- denominator_col:

  A denominator column to pass through in the same way. Its total also
  goes to `$data` as `<denominator_col>_observed`.

## Value

A `csfmt_ensemble_v3` with one draw. `$data` holds `original`, the
observed total.

## Details

The draw matrix has the name `<measure>_nowcasted`, as from
[`nowcast_delay_ecdf_v1()`](https://niphr.github.io/csalert/reference/nowcast_delay_ecdf_v1.md),
and holds the observed total. So every collapsed quantile equals the
observed total, also for the newest weeks.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 2, which scores it against
[`nowcast_delay_ecdf_v1()`](https://niphr.github.io/csalert/reference/nowcast_delay_ecdf_v1.md).

Other nowcast engines:
[`nowcast_delay_ecdf_v1()`](https://niphr.github.io/csalert/reference/nowcast_delay_ecdf_v1.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday. The
# data stops at one as-of date, so the newest weeks are still incomplete.
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

ens <- nowcast_passthrough_to_ensemble_v1(tri, max_delay_days = 21)
ens
#> <csfmt_ensemble_v3> 40 rows | 1 series | draws: numerator_nowcasted

# one draw, so every quantile equals the observed total, also for the
# newest weeks that are still incomplete
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
