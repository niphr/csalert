# Classify every draw into MEM intensity levels

Fits Moving Epidemic Method (MEM) thresholds for each season from the
earlier seasons of the same series, and classifies every draw against
them. After
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
each week has the share of its draws at each of five levels.

## Usage

``` r
mem_thresholds_v1(x, ...)

# S3 method for class 'csfmt_ensemble_v3'
mem_thresholds_v1(
  x,
  measure,
  min_seasons = 2,
  prefer_seasons = 5,
  i.seasons = 10,
  min_weeks_per_season = 30,
  exclude_seasons = NULL,
  ...
)
```

## Arguments

- x:

  The `csfmt_ensemble_v3` that holds `measure`.

- ...:

  Passed to the method.

- measure:

  The draw matrix to classify, a count or a rate.

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
  writes them, such as `"2019/2020"`. Use it for a pandemic year or a
  season with a data gap. An excluded season still gets thresholds, and
  a message names the excluded seasons in the data.

## Value

`x` with a new draw matrix, `<measure>_status`, of level codes with a
`levels` attribute. It also adds `mem_preepidemic`, `mem_medium`,
`mem_high`, `mem_veryhigh` and `mem_n_seasons`, the number of training
seasons, to `$data`. It adds them by reference, so the input ensemble
gets them too.

## Details

The fit uses the median of the draws of each week. A season is fit only
on earlier seasons: those with at least `min_weeks_per_season` weeks,
minus `exclude_seasons`, and at most the latest `i.seasons`.

A season gets no thresholds, and `NA` in every draw, in three cases:

- it has fewer than `min_seasons` training seasons,

- fewer than 2 of them hold a non-zero week,

- [`mem::memmodel()`](https://rdrr.io/pkg/mem/man/memmodel.html) fails
  with its default method and with `i.method = 3`.

A fit on fewer than `prefer_seasons` seasons is provisional, and a
message counts those seasons.

The levels, coded 1 to 5, are:

1.  `preepidemic`: below `mem_preepidemic`, the MEM epidemic threshold,

2.  `low`: below `mem_medium`, the 40% intensity threshold,

3.  `medium`: below `mem_high`, the 90% intensity threshold,

4.  `high`: below `mem_veryhigh`, the 97.5% intensity threshold,

5.  `veryhigh`: at or above `mem_veryhigh`.

It needs the mem package.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
stage 6.

Other ensemble operations:
[`ens_add_rate()`](https://niphr.github.io/csalert/reference/ens_add_rate.md),
[`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md),
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md),
[`signal_detection_hlm()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)

## Examples

``` r
# MEM needs several earlier seasons, so this series spans four:
# 212 weeks with a winter peak in each.
if (requireNamespace("mem", quietly = TRUE)) {
  w <- cstime::dates_by_isoyearweek$isoyearweek
  i <- match("2018-30", w)
  n <- 212L
  iyw <- w[i + 0:(n - 1)]
  set.seed(1)
  lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
  ens <- csfmt_ensemble_v3(
    data.table::data.table(
      isoyearweek = iyw, location_code = "nation", age = "total"
    ),
    id_cols = c("location_code", "age"),
    draws = list(numerator_nowcasted = matrix(rpois(n * 50, lam), nrow = n))
  )

  ens <- mem_thresholds_v1(ens, measure = "numerator_nowcasted")

  # each season is fit on earlier seasons only, so the first seasons get none
  print(unique(ens$data[
    !is.na(mem_high),
    .(
      season = cstime::isoyearweek_to_season_c(isoyearweek),
      mem_preepidemic, mem_medium, mem_high, mem_veryhigh, mem_n_seasons
    )
  ]))

  # every draw of a week in the first two seasons is NA
  status <- ens$draws$numerator_nowcasted_status
  print(c(
    weeks = nrow(status),
    weeks_with_no_threshold = sum(apply(status, 1, function(r) all(is.na(r))))
  ))

  # a week with thresholds gets a share of draws at each level
  r <- ens_collapse(ens, probs = 0.5)
  pcols <- grep("_status_prob_", names(r), value = TRUE)
  print(r[
    isoyearweek %in% c("2021-45", "2022-02"),
    c("isoyearweek", pcols),
    with = FALSE
  ])
}
#> mem_thresholds_v1: 3 season(s) fit on < 5 training seasons (provisional); see mem_n_seasons.
#>       season mem_preepidemic mem_medium mem_high mem_veryhigh mem_n_seasons
#>       <char>           <num>      <num>    <num>        <num>         <int>
#> 1: 2020/2021        37.26995   64.43633 81.87090     91.01148             2
#> 2: 2021/2022        40.28893   66.68661 82.29283     90.30798             3
#> 3: 2022/2023        41.83822   71.02438 81.28250     86.27663             4
#>                   weeks weeks_with_no_threshold 
#>                     212                     104 
#>    isoyearweek numerator_nowcasted_status_prob_preepidemic
#>         <char>                                       <num>
#> 1:     2021-45                                        1.00
#> 2:     2022-02                                        0.02
#>    numerator_nowcasted_status_prob_low numerator_nowcasted_status_prob_medium
#>                                  <num>                                  <num>
#> 1:                                0.00                                   0.00
#> 2:                                0.94                                   0.04
#>    numerator_nowcasted_status_prob_high
#>                                   <num>
#> 1:                                    0
#> 2:                                    0
#>    numerator_nowcasted_status_prob_veryhigh
#>                                       <num>
#> 1:                                        0
#> 2:                                        0
```
