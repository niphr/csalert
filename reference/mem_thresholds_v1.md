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
