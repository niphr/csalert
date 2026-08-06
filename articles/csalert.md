# Start here: what csalert does and which parts to use

This page is an orientation. It says what the package is for, which half
of it is current, and what it cannot do yet. It runs no analysis. For a
worked run, read
[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md).

## What csalert is for

Weekly surveillance counts arrive late. A case that belongs to last week
may not be reported for another two or three weeks. So the newest weeks
always look lower than they will turn out to be, and anything measured
on them is pulled down with them.

csalert does four things about that:

1.  **Completes the counts that are still arriving**, and says how
    uncertain each completion is.
2.  **Measures whether that completion can be trusted.** Replay the
    method against weeks that have since settled, and score how close it
    got.
3.  **Estimates recent direction.** Is the completed series rising or
    falling, and how sure can you be.
4.  **Turns a series into intensity levels and alerts.** Which of five
    seasonal levels this week sits in, and whether it is above a
    historical baseline.

## There are two generations. Use the current one.

### The current generation works on an ensemble

Every analytical step happens on a `csfmt_ensemble_v3`. An ensemble is a
table plus, for each measure, a matrix of simulated values — one column
per simulation. Uncertainty travels as those columns, not as a summary.

One rule follows, and it is the most useful thing to know about the
package:

> **Every analytical stage takes the ensemble and returns the
> ensemble**.
> [`ens_collapse()`](https://niphr.github.io/csalert/reference/ens_collapse.md)
> is **terminal**. A collapsed table is output, never input.

Collapsing reduces the simulations to quantiles. Quantiles are not
simulations, so nothing per-simulation survives it. You cannot feed a
collapsed table back into
[`short_term_trend()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
and recover a per-draw trend. Do every analytical step first, then
collapse once, at the end.

The canonical chain:

``` r
# Not run here. See vignette("pipeline", package = "csalert").
#
# csfmt_reporting_triangle_v3   the input: what was reported when
#   nowcast_quasipoisson_v1()   fill in the weeks still arriving
#   ens_add_rate()              a rate, per simulation
#   short_term_trend()          recent direction, per simulation
#   mem_thresholds_v1()         seasonal intensity level, per simulation
#   signal_detection_hlm()      above the historical baseline, per simulation
#   ens_collapse(heal = TRUE)   simulations -> quantiles. Terminal.
```

The middle stages are optional, and can be reordered among themselves.

### The old generation worked on tables directly

[`short_term_trend.csfmt_rts_data_v1()`](https://niphr.github.io/csalert/reference/short_term_trend.md)
and
[`signal_detection_hlm.csfmt_rts_data_v1()`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)
read a `cstidy` table and wrote new columns straight back onto it. There
was no simulation axis at all.

Both are **deprecated**. Both still work, and **neither warns at run
time**. An existing pipeline is therefore undisturbed, and will never
tell you it is on the old route.

**The replacement is not a drop-in.** The arguments differ, the shape of
the return value differs, and the numbers differ, because the two are
not the same estimator. Moving a call site over is a rewrite, not a
rename.
[`?short_term_trend`](https://niphr.github.io/csalert/reference/short_term_trend.md)
and
[`?signal_detection_hlm`](https://niphr.github.io/csalert/reference/signal_detection_hlm.md)
set out each difference in full.

## Where the data formats live

The table classes belong to **cstidy, not to csalert**:
`csfmt_rts_data_v1`, `v2` and `v3`. csalert consumes and returns them;
cstidy defines them.

v1 and v2 are deprecated. **v3 is the target**, and it is what
`ens_collapse(heal = TRUE)` returns.

Three facts about v3 are worth carrying with you:

- **The three classes are siblings.** None of them inherits from
  another. A v3 object is not a v2 object, so a method written for v2
  will not dispatch on it.
- **v3 derives fewer columns than v2, but removes none.** Counted on the
  unified set, v2 derives 18 columns and v3 derives 11.
  `set_csfmt_rts_data_v3()` deletes nothing, so a v2 table converted to
  v3 keeps every column it already had. What you give up is the
  *guarantee* that those columns are present, not the data.
- **v3 is weekly-only.** Its healing derives everything from
  `isoyearweek` alone. Daily and monthly data stays on v2.

## What cannot be done yet

**A v3 table cannot be written to a database today.** `csdb` ships table
validators for `csfmt_rts_data_v1` and `csfmt_rts_data_v2`, and has no
v3 equivalent.

So v3 is an analysis and presentation format. It is fine for plots,
tables and reports, and it is not yet a storage format. That is the main
limit on the direction of travel. Keep v2 wherever the result has to
reach a database.

## Where to go next

[`vignette("pipeline", package = "csalert")`](https://niphr.github.io/csalert/articles/pipeline.md)
runs one synthetic series through the whole chain, stage by stage, with
the numbers and the caveats attached to each stage. Start there when you
want code.
