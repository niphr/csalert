# MEM intensity thresholds

MEM intensity thresholds

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

  Data object.

- ...:

  Passed to methods.

- measure:

  The \`\$draws\` measure to threshold on (a rate or count).

- min_seasons:

  Hard floor of complete prior seasons needed to fit.

- prefer_seasons:

  Preferred training depth (provisional below this).

- i.seasons:

  Max seasons passed to mem::memmodel.

- min_weeks_per_season:

  Weeks needed for a season to count as training.

- exclude_seasons:

  Optional character vector of seasons (e.g. \`c("2009/2010",
  "2019/2020")\`, the \`isoyearweek_to_season_c\` form) to drop from the
  MEM training baseline – anomalous seasons (pandemic years, data gaps)
  that would distort the thresholds. Thresholds are still ESTIMATED for
  every season (including excluded ones) from its remaining non-excluded
  prior seasons; only the baseline they are fit on changes.

## Value

The \`csfmt_ensemble_v3\` with per-draw MEM intensity columns added to
\`\$draws\` (the ordinal 1..5 status for \`measure\` and its threshold
levels), so the intensity level propagates through the later quantile
collapse.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
which runs this function as stage 6 of its pipeline, on a five-season
synthetic series.

## Examples

``` r
# MEM needs several complete prior seasons, so this fixture spans four:
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

  # thresholds are estimated leave-future-out, so the early seasons get none
  print(unique(ens$data[
    !is.na(mem_high),
    .(
      season = cstime::isoyearweek_to_season_c(isoyearweek),
      mem_preepidemic, mem_medium, mem_high, mem_veryhigh, mem_n_seasons
    )
  ]))

  # A week whose season has no thresholds gets NA for every draw, so it is not
  # classified at all. On this fixture that is the first two seasons:
  status <- ens$draws$numerator_nowcasted_status
  print(c(
    weeks = nrow(status),
    weeks_with_no_threshold = sum(apply(status, 1, function(r) all(is.na(r))))
  ))

  # For a week that DOES have thresholds, every draw is classified, so the
  # alert level arrives as a distribution rather than as a single label.
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
