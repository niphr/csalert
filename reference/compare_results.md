# Compare two collapsed csfmt result sets

Compare two collapsed csfmt result sets

## Usage

``` r
compare_results(current, previous)
```

## Arguments

- current, previous:

  data.tables (or csfmt_rts_data_v3) from two runs.

## Value

A long data.table: identity + isoyearweek + column + role/q/level +
\`cur\`/\`prv\`.

## Identity columns MUST use the csfmt schema names

The value columns are found with
[`csfmt_interpret`](https://niphr.github.io/csalert/reference/csfmt_interpret.md),
which treats anything outside the csfmt structural schema as a value
column. Key the two runs on schema names such as \`location_code\` and
\`indicator_tag\`.

A non-schema identity column is a silent trap. \`location\` and
\`indicator\` are NOT in the schema, but \`location_code\` and
\`indicator_tag\` are. So \`location\` and \`indicator\` are read as
value columns. Their character values are then stacked with the numeric
measures, and \`cur\`/\`prv\` come back as character for every row. This
function still returns a table, so the damage is easy to miss. But
[`qc_week_over_week_v1`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)
then evaluates \`abs(cur - prv)\` on that character column and FAILS
with \`Error in cur - prv : non-numeric argument to binary operator\`.

Note that \`vignette("pipeline", package = "csalert")\` builds its
triangle with \`id_cols = c("indicator", "location", "age", "sex")\`.
Those names work for the nowcast pipeline itself, but a run-over-run
comparison of the result needs \`indicator_tag\` and \`location_code\`.

## See also

Neither package vignette covers run-over-run comparison.
[`qc_week_over_week_v1`](https://niphr.github.io/csalert/reference/qc_week_over_week_v1.md)
is the usual entry point; it splits this diff at the nowcast horizon.

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

# The engine is stochastic, so reset the seed inside `run()`. Without that,
# the two runs would also differ by their Monte-Carlo draws and the diff would
# confound sampling noise with the actual data revision.
run <- function(x) {
  set.seed(2)
  ens_collapse(nowcast_quasipoisson_v1(
    csfmt_reporting_triangle_v3(x, id_cols = id),
    max_delay = 3, n_sim = 200
  ))
}

# last week's run saw one reference week before it was corrected upward
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

# one row per (series, week, value column). With the seed held fixed, the only
# week that moves is the corrected one.
compare_results(cur, prv)[q == 0.5 & abs(cur - prv) > 0]
#>      time_series_id isoyearweek indicator_tag location_code    age    sex
#>              <char>      <char>        <char>        <char> <char> <char>
#> 1: d8da72e3fbb5fd29     2023-11             x        nation  total  total
#>                       column   cur   prv      role     q  level
#>                       <char> <num> <num>    <char> <num> <char>
#> 1: numerator_nowcasted_q50x0    46    31 nowcasted   0.5   <NA>
```
