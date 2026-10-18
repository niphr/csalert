# Classify the draws of a csfmt_ensemble_v4 into MEM intensity levels

Fits Moving Epidemic Method (MEM) thresholds for each season from the
earlier seasons of the same series, and classifies every draw against
them. The method is that of
[`mem_thresholds_v1()`](https://niphr.github.io/csalert/reference/mem_thresholds_v1.md)
for a `csfmt_ensemble_v3`, and the values are identical.

## Usage

``` r
mem_thresholds_v4(
  x,
  measure,
  min_seasons = 2,
  prefer_seasons = 5,
  i.seasons = 10,
  min_weeks_per_season = 30,
  exclude_seasons = NULL
)
```

## Arguments

- x:

  The `csfmt_ensemble_v4`, full or compressed.

- measure:

  The name of the draw matrix to classify, a count or a rate. It MUST
  NOT end in a reserved suffix.

- min_seasons:

  The fewest training seasons for a fit.

- prefer_seasons:

  A fit on fewer training seasons is provisional.

- i.seasons:

  The most training seasons in one fit, passed to
  [`mem::memmodel()`](https://rdrr.io/pkg/mem/man/memmodel.html).

- min_weeks_per_season:

  The fewest weeks that a training season needs.

- exclude_seasons:

  Seasons to leave out of every training set, written as
  [`cstime::isoyearweek_to_season_c()`](https://rdrr.io/pkg/cstime/man/isoyearweek_to_season_c.html)
  writes them, such as `"2019/2020"`. An excluded season still gets
  thresholds, and a message names the excluded seasons in the data.

## Value

`x` with the new draw matrix `<measure>_mem`, which holds the level
codes 1 to 5 with a `levels` attribute. It adds these columns to
`$data`:

- `<measure>_mem_thr_preepidemic`, `<measure>_mem_thr_medium`,
  `<measure>_mem_thr_high` and `<measure>_mem_thr_veryhigh`: the
  thresholds of the season of the week.

- `<measure>_mem_n_seasons`: the number of training seasons of the fit.

- `<measure>_mem_thr_postepidemic`: the post-epidemic threshold of the
  season, `epidemic.thresholds[2]` of the fit. It classifies no draw.

- `<measure>_mem_season_start` and `<measure>_mem_season_weeks`, both
  integer: `mean.start` and `mean.length` of the fit. The start is the
  rounded mean position of the first epidemic week among the season
  weeks of the fit, counted from 1. The length is the rounded mean
  epidemic length in weeks.

- `<measure>_mem_prob_preepidemic` to `<measure>_mem_prob_veryhigh`: the
  share of the draws at each level, which is `NA` when every draw is
  `NA`.

Each threshold and each fit field repeats on every week of the season,
and is `NA` in a season with no fit.

The shares give every ordinal percentile of the level codes, so the step
writes no percentile column.

Each new name MUST be at most 63 bytes. A rerun on the same `measure`
replaces the draw matrix and the columns. The input `x` does not change.

## Details

The fit uses the median of the draws of each week. A season is fit only
on earlier seasons: those with at least `min_weeks_per_season` weeks,
minus `exclude_seasons`, and at most the latest `i.seasons`. The seasons
and the season weeks come from the ISO weeks in `x$time_col`.

A season gets no thresholds, and `NA` in every draw, in three cases:

- it has fewer than `min_seasons` training seasons;

- fewer than 2 of them hold a week above 0;

- [`mem::memmodel()`](https://rdrr.io/pkg/mem/man/memmodel.html) fails
  with its default method and with `i.method = 3`.

A fit on fewer than `prefer_seasons` seasons is provisional, and a
message counts those seasons.

The levels, coded 1 to 5, are:

1.  `preepidemic`: below the MEM epidemic threshold.

2.  `low`: below the 40% intensity threshold.

3.  `medium`: below the 90% intensity threshold.

4.  `high`: below the 97.5% intensity threshold.

5.  `veryhigh`: at or above the 97.5% intensity threshold.

The function draws no random numbers. It needs the mem package. The
function takes no `...`, so a misspelt argument is an error.

## See also

Other v4 functions:
[`as_ensemble_v4()`](https://niphr.github.io/csalert/reference/as_ensemble_v4.md),
[`csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/csfmt_ensemble_v4.md),
[`csfmt_reporting_triangle_v4()`](https://niphr.github.io/csalert/reference/csfmt_reporting_triangle_v4.md),
[`ens_add_rate_v4()`](https://niphr.github.io/csalert/reference/ens_add_rate_v4.md),
[`ens_compress_v4()`](https://niphr.github.io/csalert/reference/ens_compress_v4.md),
[`nowcast_ecdf_v4()`](https://niphr.github.io/csalert/reference/nowcast_ecdf_v4.md),
[`nowcast_passthrough_v4()`](https://niphr.github.io/csalert/reference/nowcast_passthrough_v4.md),
[`print.csfmt_ensemble_v4()`](https://niphr.github.io/csalert/reference/print.csfmt_ensemble_v4.md),
[`short_term_trend_v4()`](https://niphr.github.io/csalert/reference/short_term_trend_v4.md),
[`signal_detection_hlm_v4()`](https://niphr.github.io/csalert/reference/signal_detection_hlm_v4.md)

## Examples

``` r
# MEM needs earlier seasons, so this series spans four: 212 weeks with a
# winter peak in each.
if (requireNamespace("mem", quietly = TRUE)) {
  w <- cstime::dates_by_isoyearweek$isoyearweek
  iyw <- w[match("2018-30", w) + 0:211]
  lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
  set.seed(1)
  ens <- csfmt_ensemble_v4(
    data.table::data.table(location_code = "nation", isoyearweek = iyw),
    id_cols = "location_code",
    draws = list(cases = matrix(rpois(212 * 50, lam), nrow = 212))
  )
  ens <- mem_thresholds_v4(ens, measure = "cases")
  ens$data[
    isoyearweek %in% c("2021-45", "2022-02"),
    .(isoyearweek, cases_mem_thr_high, cases_mem_prob_high)
  ]
}
#> mem_thresholds_v4: 3 season(s) fit on < 5 training seasons (provisional); see cases_mem_n_seasons.
#>    isoyearweek cases_mem_thr_high cases_mem_prob_high
#>         <char>              <num>               <num>
#> 1:     2021-45           82.29283                   0
#> 2:     2022-02           82.29283                   0
```
