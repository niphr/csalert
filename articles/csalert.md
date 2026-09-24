# Start here: what csalert does and which parts to use

This page says what the package is for, which methods are current, and
what they cannot do yet. For a worked run, read
[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md).

## What csalert is for

Weekly surveillance counts arrive late. A case from last week can take
two or three more weeks to be reported. So the newest weeks look lower
than they will be, and every trend, intensity level or alert measured on
them is too low as well.

csalert does four things:

1.  It completes the counts that are still arriving, and says how
    uncertain each completion is.
2.  It measures how far to trust that completion. It replays the method
    on weeks that have since settled, and scores the result.
3.  It estimates whether the completed series rises or falls, and how
    sure that is.
4.  It places each week in one of five seasonal intensity levels, and
    flags a week above a historical baseline.

## Use the ensemble methods

### The current methods work on an ensemble

Every analysis stage works on a `csfmt_ensemble_v3`: a table, plus a
matrix of simulated values for each measure, with one column per draw.
The uncertainty travels as those columns.

> **Every analysis stage takes the ensemble and returns the ensemble.**
> [`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md)
> is the last stage: a collapsed table is output, never input.

The collapse reduces the draws to quantiles, and no per-draw quantity
survives it. So
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
cannot get a per-draw trend back from a collapsed table. Run every
analysis stage first, and collapse once, at the end.

``` r
# Not run here. See vignette("pipeline", package = "csalert").
#
# csfmt_reporting_triangle_v3   the input: what was reported when
#   nowcast_delay_ecdf_v1()     complete the weeks still arriving
#   ens_add_rate()              a rate, per draw
#   short_term_trend()          recent direction, per draw
#   mem_thresholds_v1()         seasonal intensity level, per draw
#   signal_detection_hlm()      above the historical baseline, per draw
#   ens_collapse(heal = TRUE)   draws -> quantiles. The last stage.
```

The middle stages are optional, and their order is free, as long as each
stage finds the measure that it reads.

### The deprecated methods work on tables

[`short_term_trend.csfmt_rts_data_v1()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
and
[`signal_detection_hlm.csfmt_rts_data_v1()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)
read a `cstidy` table and write new columns onto it. They have no draws.

Both are **deprecated**. Both still work, and **neither gives a
warning**. So an existing pipeline keeps running, and never tells you
that it uses them.

**The replacement is not a drop-in.** The arguments, the shape of the
result and the numbers all differ, because the two are different
estimators. A move to the new method is a rewrite of the call.
[`?short_term_trend`](https://niphr.github.io/csalert/reference/short_term_trend.md)
and
[`?signal_detection_hlm`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)
list each difference.

## Where the data formats live

The table classes `csfmt_rts_data_v1`, `v2` and `v3` belong to
**cstidy**. csalert reads and returns them.

v1 and v2 are deprecated. **v3 is the target**, and
`ens_collapse(heal = TRUE)` returns it. Three facts about v3:

- **The three classes are siblings.** None of them inherits from
  another, so a method written for v2 does not run on a v3 object.
- **v3 derives fewer columns than v2, but removes none.** Counted on the
  unified set, v2 derives 18 columns and v3 derives 11.
  `set_csfmt_rts_data_v3()` deletes nothing, so a v2 table converted to
  v3 keeps every column it had. You lose the *guarantee* that those
  columns are present, not the data.
- **v3 is weekly only.** It derives everything from `isoyearweek`. Daily
  and monthly data stays on v2.

## What cannot be done yet

**csdb cannot validate a v3 table.** csdb ships validators for
`csfmt_rts_data_v1` and `csfmt_rts_data_v2`, and none for v3.

So use v3 for plots, tables and reports. Keep v2 where a result goes to
a database through csdb.

## Test data with a known truth

The simulators make daily counts in which you know where each outbreak
is. Run a detector on them, and check that it fires on those days.

``` r
library(csalert)
#> csalert 2026.9.24
#> https://niphr.github.io/csalert/
library(data.table)
#> 
#> Attaching package: 'data.table'
#> The following object is masked from 'package:base':
#> 
#>     %notin%

set.seed(4)
d <- simulate_baseline_data(
  start_date = "2018-01-01", end_date = "2019-12-31",
  seasonal_pattern_n = 1, weekly_pattern_n = 1,
  alpha = 3, beta = 0, gamma_1 = 0.8, gamma_2 = 0.6,
  gamma_3 = 0.8, gamma_4 = 0.4, phi = 4, shift_1 = 29
)
d <- simulate_spike_outbreak_data(d, n_sp_outbreak = 1, m = 2)
d <- add_holiday_effect(
  d,
  holiday_data = data.table(
    date = as.Date(c("2018-12-25", "2019-12-25")),
    is_holiday = TRUE
  ),
  holiday_effect = 2
)

# the days of the outbreak, and the cases it added to n
d[sp_outbreak == 2, .(first_day = min(date), last_day = max(date),
                      days = .N, cases_added = sum(sp_outbreak_n))]
#>     first_day   last_day  days cases_added
#>        <Date>     <Date> <int>       <num>
#> 1: 2019-02-05 2019-02-24    20         202
```

[`simulate_baseline_data()`](https://niphr.github.io/csalert/reference/simulate_baseline_data.md)
draws the counts from a trend, a seasonal pattern and a weekly pattern.
[`simulate_spike_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_spike_outbreak_data.md)
adds a short outbreak in the last 49 weeks, and marks its days in
`sp_outbreak`.
[`add_holiday_effect()`](https://niphr.github.io/csalert/reference/add_holiday_effect.md)
multiplies the counts on the dates you give.
[`simulate_seasonal_outbreak_data()`](https://niphr.github.io/csalert/reference/simulate_seasonal_outbreak_data.md)
adds outbreaks inside a season window. Read its help page before you use
it.
