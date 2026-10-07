# Score replayed nowcast quantiles against the settled truth

Scores a backtest from
[`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md)
against the truth from
[`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md).
It adds the weighted interval score and a 95% interval summary to the
coverage and revision columns of
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md).

## Usage

``` r
nowcast_score_v1(backtest, truth, by = "horizon", thresholds = c(0.25, 0.5))
```

## Arguments

- backtest:

  A data.table from
  [`nowcast_backtest()`](https://niphr.github.io/csalert/reference/nowcast_backtest.md),
  with the columns `reference`, `quantile_level` and `predicted`, and
  optionally `as_of` and `horizon`.

- truth:

  A data.table from
  [`nowcast_truth()`](https://niphr.github.io/csalert/reference/nowcast_truth.md),
  with the columns `reference` and `truth`.

- by:

  The columns to group the scores by.

- thresholds:

  The absolute revisions for the `p_gt_<t>` columns.

## Value

A data.table with one row per group. It has the columns of
[`nowcast_evaluate_v1()`](https://niphr.github.io/csalert/reference/nowcast_evaluate_v1.md)
except `method`, and these columns:

- `wis`: the mean WIS over the units,

- `wis_log`: the mean WIS after
  [`log1p()`](https://rdrr.io/r/base/Log.html) of each quantile and of
  the truth,

- `coverage_95`: the share of truths from the 0.025 to the 0.975
  quantile,

- `width_95_rel_median`: the median over the units of
  `(q0.975 - q0.025) / max(truth, 1)`.

`coverage_95` and `width_95_rel_median` are `NA` for a group where a
unit has no 0.025 or no 0.975 quantile.

## Details

A forecast unit is one reference week at one as-of date and horizon. The
function scores only the units that have a finite truth and the 0.05,
0.25, 0.5, 0.75 and 0.95 quantiles.

The weighted interval score (WIS) follows Bracher et al. (2021). For a
unit with truth `y` and median `m`:

    WIS  = (0.5 * |y - m| + sum_k (alpha_k / 2) * IS_k) / (K + 0.5)
    IS_k = (u - l) + (2 / alpha_k) * (l - y) * 1{y < l} + (2 / alpha_k) * (y - u) * 1{y > u}

The sum is over the `K` central intervals from the quantile pairs at
levels `p` and `1 - p`, with `p < 0.5`. Interval `k` is from `l` to `u`,
and `alpha_k = 2 * p`.

## References

Bracher J, Ray EL, Gneiting T, Reich NG (2021). Evaluating epidemic
forecasts in an interval format. PLOS Computational Biology 17(2):
e1008618.
[doi:10.1371/journal.pcbi.1008618](https://doi.org/10.1371/journal.pcbi.1008618)

## Examples

``` r
truth <- data.table::data.table(reference = "2024-01", truth = 100)
backtest <- data.table::data.table(
  reference = "2024-01", horizon = 0L,
  quantile_level = c(0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975),
  predicted = c(60, 70, 85, 95, 105, 120, 130))
nowcast_score_v1(backtest, truth)
#>    horizon     n coverage_50 coverage_90 median_signed median_abs   q05   q95
#>      <int> <int>       <num>       <num>         <num>      <num> <num> <num>
#> 1:       0     1           1           1         -0.05       0.05 -0.05 -0.05
#>    p_gt_25 p_gt_50      wis    wis_log coverage_95 width_95_rel_median
#>      <num>   <num>    <num>      <num>       <num>               <num>
#> 1:       0       0 3.357143 0.03526364           1                 0.7
```
