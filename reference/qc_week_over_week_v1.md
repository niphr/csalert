# Compare this week's run with last week's run

Splits the output of
[`compare_results()`](https://niphr.github.io/csalert/reference/compare_results.md)
at the nowcast horizon. `$integrity` lists the settled weeks whose
median changed, and `$signal` lists the status changes in the newer
weeks.

## Usage

``` r
qc_week_over_week_v1(
  current,
  previous,
  max_delay_weeks,
  tol = 1e-06,
  status_roles = c("status", "hlmstatus")
)
```

## Arguments

- current, previous:

  The output of
  [`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md)
  for this run and for the previous run. Their identity columns MUST
  have the names that
  [`compare_results()`](https://niphr.github.io/csalert/reference/compare_results.md)
  needs.

- max_delay_weeks:

  The nowcast horizon in ISO weeks. The engines take `max_delay_days`,
  in days. The names differ so that one name never means two units.

- tol:

  The largest change in a settled median that counts as no change.

- status_roles:

  The roles that hold an ordinal status. `$signal` holds only these
  roles, and `$integrity` leaves them out. The default holds `"status"`
  from
  [`mem_thresholds_v1()`](https://niphr.github.io/csalert/reference/mem_thresholds_v1.md)
  and `"hlmstatus"` from
  [`signal_detection_hlm()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md).

## Value

A list of two data.tables:

- `integrity`, with `indicator_tag`, `isoyearweek`, `column`, `prv`,
  `cur` and `abs_diff`,

- `signal`, with `indicator_tag`, `isoyearweek`, `column`, `from`, `to`
  and `change`, which is `"new"` or `"changed"`.

A table with no rows keeps `prv` and `cur`, and has no added column.
`indicator_tag` is there only when the input has it.

## Details

A week is settled when it is at least `max_delay_weeks` ISO weeks older
than the newest week of `previous`. A row in `$integrity` means that a
published number for a settled week changed, so ideally that table is
empty. It compares finite values only. `$signal` counts a new week as a
change. Both tables use the median, `q = 0.5`.

## See also

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md),
section 9.

Other quality control functions:
[`compare_results()`](https://niphr.github.io/csalert/reference/compare_results.md),
[`qc_surveillance_data_v1()`](https://niphr.github.io/csalert/reference/qc_surveillance_data_v1.md)

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

# set the seed inside `run()`, so the two runs differ only by the data
run <- function(x) {
  set.seed(2)
  ens_collapse(nowcast_delay_ecdf_v1(
    csfmt_reporting_triangle_v3(x, id_cols = id),
    max_delay_days = 21, n_sim = 200
  ))
}

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

# the engine horizon is 21 days, and this horizon is 3 weeks
qc <- qc_week_over_week_v1(cur, prv, max_delay_weeks = 3)

# the corrected week is settled, so its changed median is listed here
qc$integrity
#>    indicator_tag isoyearweek                    column   prv   cur abs_diff
#>           <char>      <char>                    <char> <num> <num>    <num>
#> 1:             x     2023-11 numerator_nowcasted_q50x0    31    46       15

# empty: these runs hold no status column, because neither
# mem_thresholds_v1() nor signal_detection_hlm() ran
qc$signal
#> Empty data.table (0 rows and 5 cols): indicator_tag,isoyearweek,column,prv,cur
```
