# Week-over-week QC: settled-data integrity (A) + frontier status signal (B)

Week-over-week QC: settled-data integrity (A) + frontier status signal
(B)

## Usage

``` r
qc_week_over_week_v1(
  current,
  previous,
  max_delay,
  tol = 1e-06,
  status_roles = c("status", "hlmstatus")
)
```

## Arguments

- current, previous:

  Two runs' collapsed csfmt.

- max_delay:

  Nowcast horizon (weeks); sets the settled/frontier boundary.

- tol:

  Tolerance for "unchanged" in the integrity check.

- status_roles:

  Naming-grammar roles treated as ORDINAL STATUS rather than as
  continuous medians: excluded from \`\$integrity\`, and the only roles
  whose transitions appear in \`\$signal\`. Defaults to both
  status-writing roles in the package – \`"status"\` from
  \[mem_thresholds_v1\] and \`"hlmstatus"\` from
  \[signal_detection_hlm\]. Before this argument existed only
  \`"status"\` was selected, so HLM alert transitions were silently
  dropped from \`\$signal\` while HLM status columns were wrongly diffed
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
w <- cstime::dates_by_isoyearweek$isoyearweek
i <- match("2023-01", w)
set.seed(1)
d <- data.table::data.table(
  isoyearweek_reference = w[i + rep(0:39, each = 3)],
  isoyearweek_reporting = w[i + rep(0:39, each = 3) + rep(0:2, 40)],
  numerator = rpois(120, c(30, 15, 5)),
  indicator_tag = "x", location_code = "nation", age = "total", sex = "total"
)
d <- d[isoyearweek_reporting <= w[i + 39]]

id <- c("indicator_tag", "location_code", "age", "sex")

# seed inside `run()`, so the two runs differ only by the data revision and
# not by their Monte-Carlo draws
run <- function(x) {
  set.seed(2)
  ens_collapse(nowcast_quasipoisson_v1(
    csfmt_reporting_triangle_v3(x, id_cols = id),
    max_delay = 3, n_sim = 200
  ))
}

cur <- run(d)
d_prv <- data.table::copy(d)
d_prv[isoyearweek_reference == w[i + 10], numerator := numerator - 5]
#> Index: <isoyearweek_reference>
#>      isoyearweek_reference isoyearweek_reporting numerator indicator_tag
#>                     <char>                <char>     <int>        <char>
#>   1:               2023-01               2023-01        26             x
#>   2:               2023-01               2023-02        20             x
#>   3:               2023-01               2023-03         8             x
#>   4:               2023-02               2023-02        38             x
#>   5:               2023-02               2023-03        16             x
#>  ---                                                                    
#> 113:               2023-38               2023-39        21             x
#> 114:               2023-38               2023-40         3             x
#> 115:               2023-39               2023-39        24             x
#> 116:               2023-39               2023-40        20             x
#> 117:               2023-40               2023-40        20             x
#>      location_code    age    sex
#>             <char> <char> <char>
#>   1:        nation  total  total
#>   2:        nation  total  total
#>   3:        nation  total  total
#>   4:        nation  total  total
#>   5:        nation  total  total
#>  ---                            
#> 113:        nation  total  total
#> 114:        nation  total  total
#> 115:        nation  total  total
#> 116:        nation  total  total
#> 117:        nation  total  total
prv <- run(d_prv)

qc <- qc_week_over_week_v1(cur, prv, max_delay = 3)

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
