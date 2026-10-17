# Fit the short-term trend of every draw of a csfmt_ensemble_v4

Fits a rolling quasi-Poisson regression of `measure` on the week index
in every draw. With `denominator`, the fit is the rate model
`measure ~ t + offset(log(denominator))`.

## Usage

``` r
short_term_trend_v4(
  x,
  measure,
  width = 3,
  denominator = NULL,
  name = measure,
  seed
)
```

## Arguments

- x:

  The `csfmt_ensemble_v4`, full or compressed.

- measure:

  The name of the draw matrix of counts in `$draws`.

- width:

  The number of weeks in a window, one whole number of at least 2.

- denominator:

  `NULL` for a count, or the name of the draw matrix of the denominator
  for a rate.

- name:

  The start of the new names. It MUST NOT end in a reserved suffix, and
  each new name MUST be at most 63 bytes.

- seed:

  The seed of the t draws, one whole number.

## Value

`x` with the new draw matrices `<name>_trend_beta1` and
`<name>_trend_se`, and these new columns in `$data`:

- `<name>_trend_pinc`: P(increasing).

- `<name>_trend_gr`: the median growth rate.

- `<name>_trend_gr_q02x5` to `<name>_trend_gr_q97x5`: the growth rate at
  the 9 percentiles 2.5, 5, 10, 25, 50, 75, 90, 95 and 97.5.

A rerun with the same `name` replaces these draw matrices and columns.

## Details

The window of a week holds that week and the `width - 1` weeks before
it. The time `t` is the week index, so the slope is a change of the log
mean per week. The fit is that of
[`stats::glm()`](https://rdrr.io/r/stats/glm.html) with the
quasi-Poisson family, and the dispersion has no floor.

Each series MUST have one row per ISO week, from its first week to its
last, as the output of
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md)
has. The function reads the weeks from `x$time_col`. It stops with an
error that names the series and the two weeks around the gap when a week
is missing or repeated. It also stops when `x$time_col` holds a value
that is not an ISO week. A week with no count MUST be a row with `NA`.

A row with an `NA` count or denominator leaves the window. A zero
denominator becomes 1 before the log, as in the v1 method. The first of
these rules that holds for a window, in one draw, decides its values:

- **Rule 3.** A window with `NA` rows and fewer than 3 rows left gets
  `NA`.

- **Rule 2.** A window where every count left is 0 gets P(increasing) 0,
  and `NA` slope, standard error and growth rate.

- **Rule 4.** A window gets `NA` when its fit does not converge, has a
  non-finite value, or has separated counts. The fit needs 3 rows, so a
  window of width 2 with a count above 0 also gets `NA`.

- Every other window gets the slope and standard error of its fit.

The first `width - 1` weeks of each series have no window and get `NA`.

P(increasing) is the mean over draws `j` of `pt(beta1_j / se_j, df_j)`.
Here `df_j` is the number of rows left in the window minus 2. A draw
with `NA` leaves the mean, and the mean of no draws is `NA`.

The growth rate is `100 * (exp(b_j) - 1)` percent per week, with
`b_j = beta1_j + se_j * t_j`. Each draw gets one `t_j` from the t
distribution with `df_j` degrees of freedom. The percentiles are over
the draws. With one draw, the function draws no random number: the
percentile `p` is then `100 * (exp(beta1 + se * qt(p, df)) - 1)`.

The function sets `seed` itself, and then puts back the random-number
state of the caller.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
[`mem_thresholds_v4()`](https://niphr.github.io/csalert/reference/mem_thresholds_v4.md),
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md),
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md),
[`print.csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v4.md),
[`signal_detection_hlm_v4()`](https://niphr.github.io/csalert/reference/signal_detection_hlm_v4.md)

## Examples

``` r
d <- data.table::data.table(
  location_code = "nation",
  isoyearweek = sprintf("2023-%02d", 1:10)
)
set.seed(1)
ens <- csfmt_ensemble_v4(
  d,
  id_cols = "location_code",
  draws = list(cases = matrix(rpois(10 * 200, 20 * exp(0.1 * 1:10)), 10))
)
ens <- short_term_trend_v4(ens, measure = "cases", width = 5, seed = 4)
ens$data[, .(isoyearweek, cases_trend_pinc, cases_trend_gr)]
#>     isoyearweek cases_trend_pinc cases_trend_gr
#>          <char>            <num>          <num>
#>  1:     2023-01               NA             NA
#>  2:     2023-02               NA             NA
#>  3:     2023-03               NA             NA
#>  4:     2023-04               NA             NA
#>  5:     2023-05        0.8524386      10.695048
#>  6:     2023-06        0.8526068       8.954959
#>  7:     2023-07        0.8814534      10.461606
#>  8:     2023-08        0.8729255       9.832097
#>  9:     2023-09        0.9110734      11.319846
#> 10:     2023-10        0.8990713      11.301626
```
