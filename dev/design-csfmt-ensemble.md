# Design: `csfmt_ensemble` and the alert-method architecture

Status: **draft for discussion** (2026-06-25). Captures the decisions and open
questions from the luftveisovervaking_trend ⇄ csalert refactor. Nothing
implemented yet.

## Motivation

`luftveisovervaking_trend`'s `action_fn` does a lot of generic work that is not
Norwegian and not luftveis-specific: nowcasting, short-term trend / growth rate,
MEM intensity thresholds, output validation, and collapsing simulation draws to
quantiles. Some of it **reinvents** what csalert already owns (`short_term_trend`
is a closed-form `rolling_slope` in luftveis, vs csalert's quasipoisson GLM), and
the home-grown version is where luftveis's growth-rate CI pathologies come from.

**Goal:** luftveis forms Norwegian data into a standard shape → csalert does the
generic statistics → luftveis makes it pretty (Norwegian formatting, flextables,
plots, quarto). The generic methods live in csalert with proper tests; the data
*formats* live in cstidy; luftveis becomes ETL + presentation.

## Core principle: two representations, one boundary

There are two axes of work, and they want different shapes:

- **Draw-parallel** work (nowcast, trend, MEM/HLM classification) reduces over the
  **draw** axis (nowcast uncertainty). Wants wide matrices.
- **Season-parallel** work (MEM/HLM *threshold estimation*) reduces over the
  **season/year** axis. Wants the point series over long history.

These meet at a single **collapse** at the very end. Everything analytical runs
**before** collapse, on the ensemble; collapse reduces all uncertainty to summary
columns; after collapse there is only presentation.

```
csfmt_reporting_triangle_v3            (input: reference × reporting)
        │  nowcast()                   creates the draw axis
        ▼
csfmt_ensemble_v3   ── trend + mem_thresholds + signal_detection_hlm
   ($data + $draws)    (all draw-aware; add columns to $draws)
        │  collapse()                  the ONE uncertainty → summary reduction; heal csfmt ONCE
        ▼
csfmt_rts_data_v3                      (everyday format: plots, tables, maps)
```

## The formats

All formats are explicitly versioned (`_vX`) and target one `csfmt_rts_data`
version (see **Versioning** below).

### `csfmt_reporting_triangle_v3` (nowcast input)

One **aggregated** row per `(series × reference × reporting)` cell: full csfmt
identity + **two** ISO-week axes + value columns.

```
granularity_geo, country_iso3, location_code, border, age, sex, indicator_tag,
isoyearweek_reference,    # when the case occurred
isoyearweek_reporting,    # when it was reported   (delay = reporting − reference, derived)
numerator, [denominator]  # two value columns on the same cell
```

Contract:

- **Aggregated counts**, keyed by `(reference, reporting)`; `delay` is derived —
  carry it as a convenience column, but reference + reporting are the source of
  truth (they cannot disagree).
- **Full csfmt identity** (same columns as the ensemble/csfmt) so `time_series_id`
  hashes identically across all three formats and conversion is trivial — the
  triangle is "a csfmt with two time axes."
- **Sparse storage, dense semantics.** The triangle is *semantically* dense (an
  absent `(reference, reporting)` cell within the observed region means a real
  `0` — reported, no cases) but may be **stored sparse** (zeros implied, like a
  sparse matrix). The format does **not** materialise a dense triangle — that is
  `nowcast()`'s job, because (a) densifying needs `max_delay` (a nowcast
  parameter, not a format property), and (b) densifying all history is wasteful:
  old reference weeks are complete and only need their *total*, while only the
  recent still-accruing weeks (within `max_delay` of now) need the dense
  `(ref × delay)` structure. `nowcast()` materialises that recent window as its
  first step.
- **Record the as-of boundary.** So "absent cell = implied 0" is unambiguous,
  carry `now = max(isoyearweek_reporting)` as metadata: absent cell with
  `reporting ≤ now` → implied `0`; `reporting > now` → does not exist yet → the
  nowcast's prediction target. (Edge case, same principle as the missing-data
  spec: a *whole* reporting week absent — no rows for `rep = W` — is "no
  submission", a structural NA, **not** all-zeros; densify must skip it.)
- **num + denom are just two value columns** on the same cell. The coherence
  requirement (`num ≤ denom` per draw) is the nowcast method's job, not the
  format's.
- Two time axes → NOT an ensemble, NOT a `csfmt_rts_data`. Consumed by `nowcast()`,
  not retained.
- Validation on construction: `reporting ≥ reference`, non-negative counts,
  complete identity.

### `csfmt_ensemble_v3` (working format)

An S3 list:

```r
structure(list(
  data  = <data.table>,   # one row per (series × week)
  draws = list(           # NULL until nowcast; keyed by MEASURE name
    "<measure>" = <matrix [nrow(data) × n_draws]>   # rows 1:1 with data
  )
), class = "csfmt_ensemble_v3")
```

`$data` invariants (enforced by the constructor — "before anything weird"):

- identity columns + `time_series_id`, `time_series_label`, `time_series_internal_id`
- **complete** time grid (no gaps)
- **sorted** by `(time_series_id, time_series_internal_id)`, keyed
- precomputed time columns (`date / isoyearweek / season / seasonweek / …`) —
  load-bearing for MEM/HLM
- plain numeric point + (after collapse) quantile columns

`$draws`:

- keyed by **measure name** (the naming grammar); the measure name carries
  provenance/role (`…_nowcasted_n`, `…_trend_gr_pr100`), so the slot is generic,
  not "nowcasted".
- each value is a `[nrow($data) × n_draws]` matrix, rows aligned **1:1** with
  `$data` (series stacked vertically).
- the matrix **columns are the anonymous draw axis** — draws are exchangeable and
  are never named; only the measure (the whole matrix) is named.
- transient: born at nowcast, accrues derived ensembles (trend, status), released
  at collapse.

### Identity: `time_series_id` is a content hash

- `time_series_id` = `xxhash64` of the canonicalised identity columns. Content
  hash (not positional integer) so it is **stable across objects and subsets** —
  survives the nowcast → trend → collapse hops.
- compute on the **unique** strata combinations, then join back — never per row.
- canonicalise before hashing: fixed identity-column set and order, consistent
  string coercion (factor→character, explicit NA token, trim), unit-separator.
- carry a readable `time_series_label` (the composite string) alongside the
  opaque hash, for debugging.

### Rows vs columns rule

> A **different time series** (different entity / stratum / indicator) is a
> **row**, identified in `time_series_id`. A **different measurement of the same
> series** (its denominator, its nowcast, its trend, its status) is a **column**,
> named by the grammar.

Test: "different time series, or the same series measured another way?"

- influenza vs RSV vs flu-subtypes vs age-bands vs locations → **rows**
- numerator vs denominator; observed vs nowcasted vs trend of the numerator → **columns**

This makes rates trivial (`num/denom` on the same row; per-draw
`$draws[["num"]] / $draws[["denom"]]`, 1:1), preserves the 1:1 draw alignment,
matches csalert's existing `value=`/`split-by-time_series_id` contract (no blast
radius), and is what luftveis already half-does. Anti-patterns ruled out:
indicators-as-columns (sparse/ragged) and numerator/denominator-as-rows (breaks
rate math).

### The seam, for free

Because `$data` is sorted by `(time_series_id, time_series_internal_id)` and the
draw matrices are row-aligned, a rolling kernel can run down the **whole** stacked
column and then invalidate windows that cross a series boundary by masking rows
where `time_series_internal_id < width`. No `by=`, no per-series split. The two
ids do double duty: alignment **and** seam masking.

## Naming grammar

Self-documenting names are valuable; the *ad-hoc* `paste0`/`str_extract` that
build them are not. Formalise the convention into a constructor + parser so names
are computed, not hand-rolled:

```r
csfmt_var(measure = "consults_r80", denom = "all", per = 100,
          role = "forecasted", q = 0.025)
#> "consults_r80_vs_all_forecasted_predinterval_q02x5_pr100"
csfmt_parse("…_q02x5_pr100")   # -> structured list
q_label(0.025) == "q02x5"; q_value("q02x5") == 0.025   # controlled vocab, reversible
```

Hierarchy: **measure identity** (named) + **statistic role** (controlled vocab:
observed/nowcasted/forecasted/trend/threshold/status) + **distribution
coordinate** (`point | q02x5 … q97x5`, controlled vocab). The **draw axis is not
in the name** — it is the matrix column index.

## Methods (all on `csfmt_ensemble_v3`, all draw-aware)

- `nowcast(triangle) → ensemble`. Consumes `csfmt_reporting_triangle_v3`, produces
  the ensemble with `$draws` populated (`nowcast_simple` = truncated-survival +
  negbin; passthrough variant for no-nowcast).
- `short_term_trend(ensemble, measure, width)`. Batched closed-form OLS: one fixed
  slope kernel applied down all draw-columns at once (the "shared design matrix").
  Adds `…_trend_gr_pr100`, `…_trend_beta1`, … matrices to `$draws`. A `method="glm"`
  path can be added later for single-series report-quality work.
- `mem_thresholds(ensemble, measure)` and `signal_detection_hlm(ensemble, measure)`.
  Two parts: **(1) estimate** thresholds from the point history (`$data`,
  draw-independent — historical weeks are final); **(2) classify** every draw of
  the recent weeks against those thresholds → a `…_status` matrix in `$draws`.
  Part (2) needs the draws, so these run **before** collapse.

### Why MEM/HLM are before collapse

The output you want is not "is the median above the epidemic threshold" but
"**what fraction of nowcast draws put us in `high` this week**". That is a
per-draw classification — only possible while the draws still exist. Collapse
first and you discard exactly the uncertainty the alert is meant to express.
Threshold *estimation* is season-parallel and draw-free; *classification* is
draw-parallel; both halves run on the ensemble, before collapse.

## `collapse()` — the single final reduction

```r
collapse <- function(ens, probs = c(.025,.05,.1,.25,.5,.75,.9,.95,.975)) {
  for (m in names(ens$draws)) {
    q <- matrixStats::rowQuantiles(ens$draws[[m]], probs = probs)
    colnames(q) <- vapply(probs, function(p) csfmt_var(measure = m, q = p), "")
    ens$data[, (colnames(q)) := as.data.table(q)]
  }
  ens$draws <- NULL
  cstidy::set_csfmt_rts_data_v3(ens$data)   # heal exactly once, here
}
```

`rowQuantiles` over each draw-matrix → named columns (nowcast quantiles, growth-
rate quantiles, and alert-level probabilities — `rowMeans(status == "high")` etc.)
→ drop `$draws` → heal the csfmt **once**. It is one-way and lossy: all
draw-level work must happen first.

`csfmt_rts_data` is the **resting/lingua-franca format** everyone speaks; the
ensemble is a short-lived computational detour that `collapse()` melts back into
it. This is what lets the self-healing csfmt be the comfortable boundary without
paying its cost in the hot loop (heal once, never inside a 1000-wide operation).

## Spec: categorical alert output (collapsing status draws)

MEM/HLM classification produces, per measure, a `…_status` matrix `[week × draw]`
of an **ordered** factor (MEM: `preepidemic < low < medium < high < veryhigh`;
HLM: `training < forecast < null < high`). Continuous draws collapse to quantiles;
categorical draws need their own reduction. Because the levels are **ordinal**,
there are two complementary summaries, and we store both:

1. **Probability mass per level** — `…_status_prob_<level>` (one column per ordered
   level), `= rowMeans(status == level)`. Sums to 1 per week. The full
   distribution; drives stacked probability-band plots and any "P(≥ level)" query
   (a cumulative sum of these).
2. **Ordinal quantiles** — `…_status_q02x5 / _q50x0 / _q97x5`, reusing the `q`
   grammar. The p-quantile of an ordinal is the **smallest level whose cumulative
   probability ≥ p** (no interpolation between categories). `q50x0` is the headline
   level; `q02x5`–`q97x5` is a credible interval: "MEDIUM (low–high)".

Rules:

- ordinal status → store **both** prob-per-level and ordinal quantiles.
- nominal (unordered) status → prob-per-level **only** (quantiles undefined).
- "are we in epidemic / above threshold X" = sum of `…_status_prob_*` at/above X;
  derivable from the columns, optionally materialise the key one
  (`…_status_prob_atleast_high`).
- grammar: add a `level` coordinate (controlled vocab = the status levels) for the
  prob columns; the `q` coordinate is reused for the ordinal CI.
  `csfmt_var(measure, role="status", level="high")` → `…_status_prob_high`;
  `csfmt_var(measure, role="status", q=0.5)` → `…_status_q50x0`.

**The single headline status** (the one word the report prints) = **`q50x0`, the
ordinal median**, which for monotone thresholds is *identical to classifying the
median rate* ("our best estimate is 38% positive → MEDIUM band"). This matches
MEM/FluNet convention, is the centre of the `q02.5–q97.5` range, and is **stable**
— it moves only when the central estimate actually crosses a threshold.
**Rejected:** the **mode** (most common level) — it flips on a 49/51 split right at
a boundary, the worst place to be jumpy, and ignores the ordering; and the
**mean of level-codes** — it assumes the levels are equally spaced, which they are
not. Ties resolved by the classification convention (`v < high → medium`,
`v >= high → high`).

Collapse mechanics: map levels → integer codes once, `rowMeans(status==L)` per
level for the prob columns, `rowCumsums` over ordered levels → first level with
cumprob ≥ p for each ordinal quantile. All vectorised row reductions, same shape
as the continuous collapse.

## Spec: rate / denominator uncertainty

Rates (`% positive = numerator / denominator`) must be computed **per draw** to
propagate uncertainty, then collapsed like any continuous measure.

**Ensemble invariant (elevated, general):** draws are **index-aligned across
measures** — column `k` of every measure's matrix is the *same Monte-Carlo
realization* of that series. So `$draws[["num"]][, k]` and `$draws[["denom"]][, k]`
are one coherent world, and any cross-measure op is column-wise.

Computing the rate (it becomes its own measure, `…_vs_…_pr100`):

- **denominator known exactly** (population, fully-reported total): broadcast —
  `rate_draws = num_draws / denom_point`.
- **denominator also nowcasted**: element-wise — `rate_draws = num_draws / denom_draws`
  (both `[week × draw]`, same draw index = coherent).

**Coherence is the nowcast's responsibility, not the rate's.** The numerator is a
*subset* of the denominator (positives ⊂ tests), so they are correlated and must
satisfy `num ≤ denom` in every draw. Nowcasting them independently can yield
`rate > 1` and wrong uncertainty. The nowcast must produce coherent pairs — e.g.
nowcast the denominator and the positivity rate and derive `num = rate × denom`, or
nowcast `denom` then `num | denom`. The rate method assumes coherence, divides, and
**asserts `num ≤ denom`** (clamp + warn on violation, never silently `>1`).

- **denom = 0 — the data stores the truth (`0`); each method substitutes locally
  as its own math requires.** Not one global policy:
  - **rate** (`num/denom`): `0/0` → **NA** (don't fabricate a 0% that reads as a
    real drop); the NA flows through trend/MEM/HLM via graceful degradation.
  - **GLM trend** (`offset(log(denom))`): `denom = 0` → substitute 1 or drop the
    week, **internally, local to the fit** (log(0) breaks); never written back.
  - Principle: honest data in, method-local edge handling. The format never
    carries a fudged denominator.

**Payoff — `trend_fraction` disappears.** Once the rate is a first-class measure
with its own draw matrix, "trend of a rate" is just `short_term_trend` on the
`…_pr100` measure — the same batched kernel, no `trend_fraction` TRUE/FALSE
branching. The current three-way `if` in luftveis's `action_fn` collapses to "pick
the measure to trend."

## Spec: missing data (zero vs NA)

Complete-grid expansion forces the question: is an absent week a true **0**
(surveillance ran, no cases) or **NA** (no data)? The raw data often can't say, so
the rule is **let the denominator decide** — it is the "surveillance was active"
signal:

- rate indicators: **denom present + num absent → `num = 0`** (testing happened, no
  positives); **denom absent → NA** (no testing → unknown).
- count-only indicators (no denom): **within the series' observed span → 0, outside
  → NA**, using `cstidy::identify_data_structure` to find the active span.
- per-source override where the data genuinely distinguishes the two.

NA propagation, stated once: rolling-trend window containing NA → NA; MEM/HLM
baseline → drop NA weeks (`na.omit`); collapse → `rowQuantiles(na.rm)`; rate → any
NA input → NA.

**Low counts: report, don't suppress — because v3 finally gives an honest
interval.** At low counts the growth-rate point estimate can be wild (the old
+7000%), but with draws the `q02.5–q97.5` interval blows up naturally and
self-flags "we don't know." So report the estimate **with its draw-based interval,
never the bare point**, and keep the `validate_trend_output` warning for the absurd
tail.

Principle: **don't hide, don't fabricate — the denominator disambiguates
zero-vs-missing, the draw-based interval exposes low-count noise.**

## Spec: number of draws & reproducibility

**Size the draw count by the most demanding output you publish — the tail
quantiles — not the cheapest (the median headline).** Measured Monte-Carlo wobble
(same uncertainty, 2000 re-seeds, NegBin example):

| quantile | wobble @ 100 draws | wobble @ 1000 |
|---|---|---|
| q02.5 (lower CI) | ±14% of value | ±5% |
| q50 (headline) | ±5% | ±1.8% |
| q97.5 (upper CI) | ±7% | ±2.5% |

At n=100 the published 95% interval jitters week-to-week from noise alone
(~2–3 draws define each tail). **Default `n_draws = 1000`** — ~25 draws per tail,
tails settle to ~2.5% (the ~3× improvement is just √10). The batched architecture
already makes 1000 cheap (trend ~110 ms + collapse ~40 ms / indicator), so there
is no speed reason to cut. Only drop toward ~100–200 if you stop publishing 95%
intervals and report median + a coarse level — a *reporting* decision, not a
default.

**Reproducible ≠ accurate.** A fixed seed makes a run reproducible, but n=100 is a
reproducibly *noisier estimate* of the true posterior interval. Carry
`n_draws` and the RNG seed as ensemble metadata; seed for reproducibility, size
`n_draws` for accuracy of the tails.

## Performance (measured, bit-identical to current)

Per indicator, 300 weeks × 1000 draws, on this machine:

| op | long + `by=nowcast_id` | wide naive (cbind) | wide matrix-native | diff |
|---|---|---|---|---|
| trend | ~140 ms | ~230 ms | **~110 ms** | `0` |
| collapse (9 q) | ~140 ms | — | **~40 ms** (`rowQuantiles`) | `0` |
| memory | 3.6 MB | — | **1.2 MB** | — |

Notes: the trend win is modest (~1.3×) and **only** if matrix-native (cumsum-diff,
not `cbind`/lists — the naive wide version is *slower*). The real wins are
**collapse (~3.5×), memory (~3×), seam-safety, and composability**. The no-nowcast
passthrough drops from 1000 identical columns to 1 — a much larger memory win on
those indicators.

## Versioning (decision needed)

The csverse is **split by install, not by source**:

- **cstidy source (github/niphr) is 2025.10.27 and has both `csfmt_rts_v1.R` and
  `csfmt_rts_v2.R`.** v2 is real and current.
- the **installed** cstidy on this machine is the stale **2023.5.24** (v1 only).
- norsyss.cs9 (live) uses **v2**; csalert uses **v1**.

**Decision:** build the **v3 cohort**. All new formats share `_v3` to signal they
are one generation, designed to interoperate: `csfmt_reporting_triangle_v3`,
`csfmt_ensemble_v3`, and a **clean `csfmt_rts_data_v3`** (no `[` self-healing —
explicit `heal()`, content-hash `time_series_id`, `time_series_internal_id`, the
naming grammar baked in). `collapse()` targets `csfmt_rts_data_v3`.

This commits to building `csfmt_rts_data_v3`, not collapsing to the existing v2.
Mitigation is **coexistence**: v3 ships clean and v2 stays alive for legacy
consumers (csstyle, csmaps, norsyss.cs9) until they migrate — different classes,
incremental migration, no big-bang. Upgrade this machine's cstidy to 2025.10.27
as the base to build v3 on. (`_v3` on never-before-existing formats like the
triangle/ensemble is cohort-versioning, not iteration-versioning — chosen for
consistency across the generation.)

### What the "self-healing" actually is (and why the ensemble must avoid it)

In `csfmt_rts_data_v2` the **`[` operator is overridden** (`[.csfmt_rts_data_v2`).
On every subset/assignment it strips the class, re-evaluates, and re-applies the
class; and for any time/geo assignment it runs **"smart assignment"** —
`deparse` the call → regex-detect the modified time var → `glue` R source →
**`eval(parse(text=…))`** to impute the derived columns. So a single
`d[, isoyearweek := x]` triggers deparse + regex + codegen + `eval(parse())`.

This is the cost you do **not** want in a 1000-wide hot loop, and it's why the
architecture keeps the draw-parallel work on **bare matrices** (`$draws`) and only
constructs/heals the csfmt **once**, in `collapse()`. When operating on `$data`
during compute, use `cstidy::remove_class_csfmt_rts_data()` to drop to a plain
data.table and re-class only at the boundary — never let the `[` override fire
inside the loop.

### `time_series_id`: we deliberately diverge from cstidy

`unique_time_series.csfmt_rts_data_v2` assigns `time_series_id := 1:.N` — a
**positional integer**, unstable across objects/subsets. Our ensemble uses a
**content hash** instead (stable across the nowcast→trend→collapse hops). Decide
whether to upstream the hash into cstidy's `unique_time_series` or keep it
ensemble-local. (cstidy already groups by the right identity columns —
`granularity_*`, `location_code`, `border`, `age`, `sex`, `*_id`, `*_tag` — so the
change is just integer → hash.)

## Migration: v2 ↔ v3 by S3 dispatch

Version = class, so v2 and v3 coexist with **zero conditional branching**:
`method.csfmt_rts_data_v2` and `method.csfmt_rts_data_v3` are two methods on the
same generic; `method(x)` dispatches on `x`'s class. Old code passing v2 objects
keeps hitting the old path; new code passes v3 and hits the new path. Even
`[.csfmt_rts_data_v2` (the magic heal) vs a plain `[` on v3 coexists, because `[`
is S3 too. Migration is file-by-file / consumer-by-consumer, no big-bang.

What makes it *safe* (not just mechanically possible):

1. **Shared generic.** Both methods register on the same `UseMethod` generic
   (csalert already has it). New-only methods (nowcast, ensemble, mem-on-ensemble)
   have no v2 counterpart — fine; v2 just lacks that capability.
2. **`as_csfmt_rts_data_v3(x)` converter is required infra** — without it the two
   worlds are isolated islands. Migrating a consumer = convert to v3 at its
   boundary, then use v3 methods.
3. **v2 is frozen / maintenance-only.** Coexistence is migration *runway*, not
   permanent parallel development — all new work on v3, never dual-maintain two
   `short_term_trend`s (they would drift).
4. **The numbers differ on v3 intentionally** (batched trend, proper CIs). So the
   v2→v3 flip is exactly where the **equivalence gate** earns its keep: it
   classifies each difference as intended improvement vs accidental regression.
   Dispatch makes the swap smooth; it does not remove the need to verify numbers
   at the flip.

## OOP decision: S3 for data, R6 for orchestration, not S7

> **R6** for stateful behavior and orchestration (cs9 tasks, DB handles, plan
> execution — already R6). **S3-on-data.table** for data and its transformations
> (cstidy formats, `csfmt_ensemble`, csalert methods). **S7 not adopted.**

Reasoning:

- **csfmt is a data.table.** R6/S7 hide it behind methods/properties and break
  interop — an R6/S7 object is not a `data.frame`, so it won't pass to ggplot,
  csmaps, flextable, dplyr, cstidy without unwrapping.
- **S7's safety doesn't fire where it matters.** S7 validates on `@<-` and
  construction; the dominant mutation here is `dt[, col := val]`, which modifies in
  place and never calls `@<-`. Formalism cost, no payoff on the hot path. (And the
  v2 pain is the `[` override, not S3 — fix that, don't switch OOP systems.)
- **The ensemble is a value transformed by a functional pipeline**
  (`ens |> nowcast() |> short_term_trend(...) |> collapse()`), matching csalert's
  S3 generics and letting one generic dispatch on both a plain csfmt and an
  ensemble. R6's in-place-mutation "speed win" is illusory: methods *add* keys to
  `$draws` (shallow list-spine copy, not matrix copies), and the hot loop runs on
  bare matrices, not the object. Reference semantics are a footgun for a data
  object (accidental aliasing).
- **R6 belongs on the outside** (the cs9 task drives the S3 methods on S3 data).
  Don't cross the streams.

So: `csfmt_ensemble` = **S3 list + `validate_ensemble()`**. Format = S3. R6 stays
the cs9 orchestration layer.

## Further topics to cover (not yet specced)

Process/discipline items still to nail (the data-shape specs are now resolved
above):

- **Per-series failure isolation.** One series that won't fit (MEM no-converge,
  GLM diverge, too little history) must yield NA columns and a warning, never kill
  the batch. Make graceful degradation a cross-cutting contract (it's already how
  `add_mem_thresholds` behaves).
- **Testing philosophy.** Synthetic-ground-truth (we know the answer) + property
  tests + golden fixtures, ported from the luftveis suite (`make_growth_series`,
  `make_mem_seasons`, `simulate_truncated`) as the seed for csalert.
- **Memory at scale.** Don't hold every indicator's `$draws` at once — collapse
  per series and keep only the collapsed csfmt. State the lifecycle bound.
- **Package ownership.** A table of who owns what: ensemble class + grammar +
  formats (cstidy), nowcast/trend/mem/hlm/validators (csalert), ETL + Norwegian
  formatting + plots (luftveis). Avoids boundary drift.
- **Performance target.** "Fast" needs a number — e.g. full p1 over ~50
  indicators × ages in < N minutes — or it's unfalsifiable.
- **What stays Norwegian (anti-leak boundary).** Decimal comma, location
  hierarchies, holiday/`quality_control` timing must NOT leak into csalert. The
  generic methods stay country-agnostic.
- **Parallelism.** Per-series work is embarrassingly parallel; note how (if at all)
  it composes with cs9's `callr`/parallel task execution.

## Open gaps

_(Resolved and moved into specs above: reporting-triangle contract, NA/zero policy,
categorical alert output, rate/denominator uncertainty, draws & reproducibility,
migration mechanism.)_

1. **csalert has no test harness** — precondition (Phase 0). Everything we move
   lands in an unverified package until testthat exists. Port the luftveis
   nowcast/trend/MEM tests as the landing zone.
2. **Build `csfmt_rts_data_v3`** — the v3 cohort commits to a clean cstidy format
   (no `[` self-healing, hash id, `internal_id`, grammar). Upgrade cstidy to
   2025.10.27 as the base.
3. **Self-healing cost unmeasured** — confirm "heal once" matters by quantifying the
   per-heal cost.
4. **Equivalence-gate details** — what counts as "same enough" when a consumer
   flips v2 → v3 (intended improvement vs regression).
5. **Granularity** — weekly-only for now; daily/mixed out of scope, state it.
6. **Stakeholder buy-in** — the v3 cohort touches cstidy/csalert/norsyss.cs9;
   needs the maintainers' sign-off before code moves.
7. **Canonical quantile probability set** — fixed vs configurable (minor).

## Phase 1 outcomes & process resolutions (#4)

The engine is built (see the csalert `phase1-ensemble-engine` branch). Resolutions
to the process items:

**Performance target — met with huge margin.** Measured `action_fn_csalert`
(triangle → nowcast → trend → collapse → heal, 1000 draws): **~55 ms per
indicator**; **~3 s** for ~50 indicators × ages **serial**. So a sane target is
"p1 computation < 30 s" and it clears it ~10×. The real weekly-report cost is the
**network data load + quarto render**, not the statistics — so no compute
optimization or parallelism is needed. (The batched/wide design is what makes
1000 draws this cheap.)

**Parallelism — not needed.** Series are embarrassingly parallel and the engine
already vectorizes over the draw axis, but at ~3 s serial there is nothing to
parallelize. If the indicator set grew 10×, luftveis could parallelize the
per-indicator `action_fn_csalert` calls via `plnr`/`callr` (the cs9 task layer
already does this) — each call is independent.

**Blast radius — additive only.** The csalert work **adds** new files and new S3
methods on existing generics (`short_term_trend.csfmt_ensemble_v3`,
`mem_thresholds`, `nowcast`, …); it changes **no existing function signature**.
The pre-existing methods (`short_term_trend.csfmt_rts_data_v1`,
`signal_detection_hlm.csfmt_rts_data_v1`, `prediction_interval`, `row_*`) and
their seed tests are untouched and still pass. So existing csalert consumers are
unaffected; v2 is likewise untouched in cstidy.

**Package ownership.**

| package | owns |
|---|---|
| **cstidy** | the formats: `csfmt_rts_data_v3` (clean weekly), `csfmt_reporting_triangle_v3`*, `csfmt_ensemble_v3`*, the naming grammar* (\*currently in csalert; promote to cstidy when stable) |
| **csalert** | the methods: `nowcast`, batched `short_term_trend`, `mem_thresholds`, `signal_detection_hlm`, `add_rate`, `collapse`, validators |
| **luftveis** | `get_data`, the luftveis→triangle mapping (`action_fn_csalert`), Norwegian formatting/prt, flextables, plots, quarto; the equivalence gate |
| **cs9** | orchestration (tasks, DB, plan execution) — R6, unchanged |

**Buy-in — materials ready, the act is human.** The design doc (this file + the
HTML), the working branches, and the green test suites are the artefacts to
circulate to Beatriz/Chi/Trude. Securing agreement on the v3 cohort is the one
step that can't be automated.

## Suggested sequencing

0. Stand up **testthat in csalert** (precondition) + settle the csfmt version.
1. Formats in **cstidy**: `csfmt_reporting_triangle_v3`, `csfmt_ensemble_v3`,
   naming grammar (`csfmt_var`/`csfmt_parse`, `q_label`/`q_value`), the constructor
   invariants.
2. `nowcast()` into csalert + port nowcast tests.
3. Batched `short_term_trend` (delete luftveis `rolling_slope`); decide the draws
   contract; port trend tests.
4. `mem_thresholds` + draw-aware classification into csalert; port MEM tests.
5. Move validators in.
6. Shrink luftveis to: `get_data → to_reporting_triangle → csalert::* → collapse →
   format/plot`.
