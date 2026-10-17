# The v4 tasks for norsyss.cs9

These are the specs of the 3 v4 tasks that norsyss.cs9 wires: the short-term trend, HLM and MEM. The norsyss.cs9 session owns the wiring. csalert supplies the functions and these specs. `data-raw/v4_norsyss_validation.R` checks every spec against the real v4 output on the national series of `norsyss_respiratory_v1_2026-10-13.csv`.

## Rules for every task

- Each task reads `anon_norsyss_data` directly, as the current trend and HLM tasks do. norsyss.cs9 has no reporting delay, so no task builds a reporting triangle or a nowcast.
- Rename the counts to `numerator` and `denominator`. The numerator is `consultations_icpc2group_n`. The denominator is `consultations_all_n` for a group where `includes_influenza_covid19` is `TRUE`, and `consultations_without_influenza_covid19_n` for every other group, as in the current tasks.
- The identity columns of a series are `granularity_geo`, `location_code`, `age`, `sex`, `tariffgroup_tag` and `icpc2grp_tag`. Pass them as `id_cols`.
- Each task builds its ensemble with `csfmt_ensemble_v4()`, with one draw per measure. `csfmt_ensemble_v4()` needs a data.table, so a table that DBI reads MUST go through `data.table::setDT()` first.

```r
d <- data.table::setDT(d)
x <- csfmt_ensemble_v4(
  d[, c(id_cols, "isoyearweek"), with = FALSE],
  id_cols = id_cols,
  draws = list(numerator = as.matrix(d$numerator), denominator = as.matrix(d$denominator))
)
```

## The tables

The SQL below shows each table as cs9 and csdb 2026.10.18 create it. The compute measurement of 2026-10-17 read these definitions from PostgreSQL 18.

- In the cs9 `field_types`, write `TEXT` for a text column, which csdb creates as `character varying`. Write `DOUBLE`, which csdb creates as `double precision`. A season count is `INTEGER`.
- cs9 adds the column `auto_last_updated_datetime` to every table. The task does not write it.
- Tasks 1 and 2 write a partitioned table. Their cs9 `keys` are the 5 identity columns other than `icpc2grp_tag`, and `isoyearweek`. cs9 adds the partition column `icpc2grp_tag` itself. That column allows `NULL` and is not in the unique index. Every row of a partition has the same tag, so the index still keeps the rows unique.
- Task 3 writes a table with no partitions. Its `keys` are the 6 identity columns and `isoyearweek`, so `icpc2grp_tag` is `NOT NULL` and in the unique index.
- Each table has its unique index and no other index. Do not add the `ind1` index of the v1 tables.
- The columns of the unique index are `NOT NULL`. Every other column allows `NULL`, because a quantile, a probability or a threshold is `NULL` where the method gives no value.
- Each name is at most 63 UTF-8 bytes, the PostgreSQL limit. The validation script checks every table, column and partition name in this file.
- The tables hold few of the csfmt_rts_data_v2 columns. Use `csdb::validator_field_types_blank` and `csdb::validator_field_contents_blank`.
- Each task empties its table on the first plan and writes every week of its output. No task writes only the changed weeks.

## The plans

Tasks 1 and 2 have one plan per ICPC-2 group, and each plan writes one partition. cs9 names a partition `<table>_xxpxx_<tag>`. The longest is `anon_lss_short_term_trends_v4_xxpxx_respiratory_infections`, at 58 bytes. A plan holds the 189 series of the current trend and HLM tasks. They are 21 locations (1 nation, 5 georegions and 15 counties at border 2024) by 9 ages, with `sex = "total"`.

Task 3 has one plan, the `r80` partition of `anon_norsyss_data`, and writes one table.

The expected rows per plan:

| Task | Table | Rows per plan | For 2006-01 to 2026-41 |
|---|---|---|---|
| 1. trend | `anon_lss_short_term_trends_v4` | one row per series and week, from the first week of the series to its last | 1,084 per series; at most 204,876 |
| 2. HLM | `anon_lss_signals_v4` | the rows of task 1 that have a limit | 823 per series; at most 155,547 |
| 3. MEM | `anon_r80_mem_v4` | the `r80` rows of `anon_norsyss_data` in ISO weeks 1 to 20 and 40 to 52 | 682 per series; at most 128,898 |

The counts per series are measured on the national series of the csv. The maxima assume that all 189 series hold every week.

## Task 1: the short-term trend

The trend fits the count with the denominator as the offset, so it models the rate. The window is 5 weeks, as in the current task. A week is increasing when `numerator_vs_denominator_pr100_trend_pinc >= 0.95`, which is `1 - alpha / 2` with the current `alpha = 0.10`. With one draw, the step gives the growth-rate percentiles in closed form.

```r
x <- short_term_trend_v4(x, measure = "numerator", width = 5, denominator = "denominator", name = "numerator_vs_denominator_pr100", seed = 4)
out <- x$data[, c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

Here `x` is the ensemble from the rules, and `new_cols` are the 11 columns that the step adds, as below. The first 4 weeks of a series have no window, and their values are `NULL`.

```sql
CREATE TABLE anon_lss_short_term_trends_v4 (
  granularity_geo CHARACTER VARYING NOT NULL,
  location_code CHARACTER VARYING NOT NULL,
  age CHARACTER VARYING NOT NULL,
  sex CHARACTER VARYING NOT NULL,
  tariffgroup_tag CHARACTER VARYING NOT NULL,
  isoyearweek CHARACTER VARYING NOT NULL,
  numerator_vs_denominator_pr100_trend_pinc DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q02x5 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q05x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q10x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q25x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q50x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q75x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q90x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q95x0 DOUBLE PRECISION,
  numerator_vs_denominator_pr100_trend_gr_q97x5 DOUBLE PRECISION,
  icpc2grp_tag CHARACTER VARYING,
  auto_last_updated_datetime TIMESTAMP WITHOUT TIME ZONE,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek)
);
```

## Task 2: HLM

HLM compares the rate with the limit of a 5-year baseline, as in the current task. A week is high when `numerator_vs_denominator_pr100_hlm_prob_high` is 1. v4 flags a value at the limit as high, where v1 flags only a value above it.

A week has no limit when its baseline is not complete. The first 261 weeks of a series have no limit: 5 years of 52 weeks, and 1 more week. The task drops every row without a limit before the write, as v1 does. It drops them from the output only. The ensemble keeps them, because the limit of a later week uses them.

```r
x <- ens_add_rate_v4(x, numerator = "numerator", denominator = "denominator", per = 100, name = "numerator_vs_denominator_pr100")
x <- signal_detection_hlm_v4(x, measure = "numerator_vs_denominator_pr100", baseline_isoyears = 5)
out <- x$data[!is.na(numerator_vs_denominator_pr100_hlm_thr), c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

Here `new_cols` are the 3 columns that the step adds, as below.

```sql
CREATE TABLE anon_lss_signals_v4 (
  granularity_geo CHARACTER VARYING NOT NULL,
  location_code CHARACTER VARYING NOT NULL,
  age CHARACTER VARYING NOT NULL,
  sex CHARACTER VARYING NOT NULL,
  tariffgroup_tag CHARACTER VARYING NOT NULL,
  isoyearweek CHARACTER VARYING NOT NULL,
  numerator_vs_denominator_pr100_hlm_thr DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_prob_null DOUBLE PRECISION,
  numerator_vs_denominator_pr100_hlm_prob_high DOUBLE PRECISION,
  icpc2grp_tag CHARACTER VARYING,
  auto_last_updated_datetime TIMESTAMP WITHOUT TIME ZONE,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek)
);
```

## Task 3: MEM

MEM reads the `r80` partition of `anon_norsyss_data` in ISO weeks 1 to 20 and 40 to 52, the weeks of `r80_estimate_mem_thresholds`. Filter the rows before `csfmt_ensemble_v4()`. On all weeks of the national series, the v4 pre-epidemic threshold differs from the v1 fit by up to 16%. The other arguments are those of `r80_estimate_mem_thresholds`: `i.seasons = 10` and the 4 excluded seasons.

```r
d <- data.table::setDT(d)[as.integer(substr(isoyearweek, 6, 7)) %in% c(1:20, 40:52)]
# then build x from d as the rules say
x <- ens_add_rate_v4(x, numerator = "numerator", denominator = "denominator", per = 100, name = "numerator_vs_denominator_pr100")
x <- mem_thresholds_v4(x, measure = "numerator_vs_denominator_pr100", min_seasons = 2, i.seasons = 10, exclude_seasons = c("2009/2010", "2019/2020", "2020/2021", "2021/2022"))
out <- x$data[, c(id_cols, "isoyearweek", new_cols), with = FALSE]
```

Here `new_cols` are the 10 columns that the step adds, as below. On the national series, each of the 4 thresholds is within 0.02% of the v1 fit in each of the 17 seasons that both fit. The v1 rate is rounded to 3 decimals, and the v4 rate is not. v4 also fits 2008/2009 and 2009/2010, which norsyss.cs9 leaves out as the first 5 seasons of the data.

The task covers only `r80` and the rate of the v1 `fhi` tables. That rate is the share of all consultations, on the 9 ages of the 189 series. The task does not cover these outputs of v1:

- the per-100,000 rate of the v1 `tessy` tables;
- the `r80` ages `015_064` and `065p`.

```sql
CREATE TABLE anon_r80_mem_v4 (
  granularity_geo CHARACTER VARYING NOT NULL,
  location_code CHARACTER VARYING NOT NULL,
  age CHARACTER VARYING NOT NULL,
  sex CHARACTER VARYING NOT NULL,
  tariffgroup_tag CHARACTER VARYING NOT NULL,
  isoyearweek CHARACTER VARYING NOT NULL,
  numerator_vs_denominator_pr100_mem_thr_preepidemic DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_medium DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_high DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_thr_veryhigh DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_n_seasons INTEGER,
  numerator_vs_denominator_pr100_mem_prob_preepidemic DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_low DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_medium DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_high DOUBLE PRECISION,
  numerator_vs_denominator_pr100_mem_prob_veryhigh DOUBLE PRECISION,
  icpc2grp_tag CHARACTER VARYING NOT NULL,
  auto_last_updated_datetime TIMESTAMP WITHOUT TIME ZONE,
  UNIQUE (granularity_geo, location_code, age, sex, tariffgroup_tag, isoyearweek, icpc2grp_tag)
);
```
