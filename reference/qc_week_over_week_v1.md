# Week-over-week QC: settled-data integrity (A) + frontier status signal (B)

Week-over-week QC: settled-data integrity (A) + frontier status signal
(B)

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

  Two runs' collapsed csfmt.

- max_delay_weeks:

  Nowcast horizon in reference WEEKS. It sets the settled/frontier
  boundary on the ISO-week axis, so it windows reference weeks and never
  delay days. The nowcast engines take \`max_delay_days\` instead,
  counted in DAYS. The two names differ because the two units differ,
  and one name for both is the defect this rename removes.

- tol:

  Tolerance for "unchanged" in the integrity check.

- status_roles:

  Naming-grammar roles treated as ORDINAL STATUS rather than as
  continuous medians: excluded from \`\$integrity\`, and the only roles
  whose transitions appear in \`\$signal\`. Defaults to both
  status-writing roles in the package – \`"status"\` from
  \[mem_thresholds_v1\] and \`"hlmstatus"\` from
  \[signal_detection_hlm\]. Before this argument existed, only
  \`"status"\` was selected. HLM alert transitions were then silently
  dropped from \`\$signal\`, and HLM status columns were wrongly diffed
  as continuous values in \`\$integrity\`.

## Value

\`list(integrity = \<A\>, signal = \<B\>)\`.

## See also

Neither package vignette covers run-over-run comparison.
[`compare_results`](https://niphr.github.io/csalert/reference/compare_results.md)
is the underlying diff, and documents which identity column names this
check needs.
[`qc_surveillance_data_v1`](https://niphr.github.io/csalert/reference/qc_surveillance_data_v1.md)
answers a different question, about one input feed rather than two
finished runs.

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

# seed inside `run()`, so the two runs differ only by the data revision and
# not by their Monte-Carlo draws
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

# the engine horizon is 21 DAYS; this one is 3 WEEKS, and the names say so
qc <- qc_week_over_week_v1(cur, prv, max_delay_weeks = 3)

# A settled week whose published median moved between runs. This table is
# ideally empty; a row in it means history was rewritten.
qc$integrity
#>    indicator_tag isoyearweek                    column   prv   cur abs_diff
#>           <char>      <char>                    <char> <num> <num>    <num>
#> 1:             x     2023-11 numerator_nowcasted_q50x0    31    46       15

# Status transitions on the frontier weeks. Empty here because these runs
# carry no status column at all: mem_thresholds_v1() writes role "status" and
# signal_detection_hlm() writes role "hlmstatus", and neither was run. Both
# roles are selected by default -- see `status_roles`.
qc$signal
#> Empty data.table (0 rows and 5 cols): indicator_tag,isoyearweek,column,prv,cur
```
