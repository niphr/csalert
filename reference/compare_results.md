# Compare two collapsed result sets, column by column

Joins two runs on `time_series_id` and `isoyearweek`, and returns one
row per series, week and value column.
[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md)
finds the value columns of `current`, and the parts of each name.

## Usage

``` r
compare_results(current, previous)
```

## Arguments

- current, previous:

  The output of
  [`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md)
  for two runs.

## Value

A long data.table with `time_series_id`, `isoyearweek`, the columns
among `indicator_tag`, `location_code`, `age` and `sex` that exist, and:

- `column`: the name of the value column,

- `cur`, `prv`: its value in `current` and in `previous`,

- `role`, `q`, `level`: the parts of its name.

## Details

`time_series_id` is a hash of the identity columns, so a series has the
same id in both runs. A week in only one run gets `NA` for the other
run.

## Identity columns MUST use the csfmt schema names

[`csfmt_interpret()`](https://niphr.github.io/csalert/reference/csfmt_interpret.md)
reads every column outside the csfmt schema as a value column.
`location_code` and `indicator_tag` are schema names, but `location` and
`indicator` are not. So with `location` or `indicator`, `cur` and `prv`
become character.

This function still returns a table.
[`qc_week_over_week_v1()`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)
then stops with `non-numeric argument to binary operator`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
section 9.

Other quality control functions:
[`qc_surveillance_data_v1()`](https://niphr.github.io/csalert/reference/qc_surveillance_data_v1.md),
[`qc_week_over_week_v1()`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)

## Examples

``` r
# 40 reference weeks, each reported 3, 10 and 17 days after its Monday
mondays <- as.Date("2023-01-02") + 7 * (0:39)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = format(rep(mondays, each = 3), "%G-%V"),
  reporting_date = rep(mondays, each = 3) + rep(c(3, 10, 17), 40),
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[reporting_date <= mondays[40] + 6]

id <- c("indicator_tag", "location_code", "age", "sex")

# Set the seed inside `run()`. Then the two runs differ only by the data
# revision, and not by their Monte-Carlo draws.
run <- function(x) {
  set.seed(2)
  ens_collapse(nowcast_delay_ecdf_v1(
    csfmt_reporting_triangle_v3(x, id_cols = id),
    max_delay_days = 21, n_sim = 200
  ))
}

# last week's run saw one reference week before a correction raised it
cur <- run(d)
d_prv <- data.table::copy(d)
d_prv[
  isoyearweek_reference == format(mondays[11], "%G-%V"),
  numerator := numerator - 5
]
#> Index: <isoyearweek_reference>
#>      isoyearweek_reference reporting_date numerator indicator_tag location_code
#>                     <char>         <Date>     <int>        <char>        <char>
#>   1:               2023-01     2023-01-05        26             x        nation
#>   2:               2023-01     2023-01-12        20             x        nation
#>   3:               2023-01     2023-01-19         8             x        nation
#>   4:               2023-02     2023-01-12        38             x        nation
#>   5:               2023-02     2023-01-19        16             x        nation
#>  ---                                                                           
#> 113:               2023-38     2023-09-28        21             x        nation
#> 114:               2023-38     2023-10-05         3             x        nation
#> 115:               2023-39     2023-09-28        24             x        nation
#> 116:               2023-39     2023-10-05        20             x        nation
#> 117:               2023-40     2023-10-05        20             x        nation
#>         age    sex
#>      <char> <char>
#>   1:  total  total
#>   2:  total  total
#>   3:  total  total
#>   4:  total  total
#>   5:  total  total
#>  ---              
#> 113:  total  total
#> 114:  total  total
#> 115:  total  total
#> 116:  total  total
#> 117:  total  total
prv <- run(d_prv)

# with the seed held fixed, only the corrected week moves
compare_results(cur, prv)[q == 0.5 & abs(cur - prv) > 0]
#>      time_series_id isoyearweek indicator_tag location_code    age    sex
#>              <char>      <char>        <char>        <char> <char> <char>
#> 1: d8da72e3fbb5fd29     2023-11             x        nation  total  total
#>                       column   cur   prv      role     q  level
#>                       <char> <num> <num>    <char> <num> <char>
#> 1: numerator_nowcasted_q50x0    46    31 nowcasted   0.5   <NA>
```
