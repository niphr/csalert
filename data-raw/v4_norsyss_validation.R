# The v4 validation on real NorSySS series: v4 against v1, and the checks of
# the norsyss.cs9 task specs in data-raw/v4-norsyss-tasks.md.
#
# Run it from the package root:
#   Rscript data-raw/v4_norsyss_validation.R \
#     --csv=<local copy>/norsyss_respiratory_v1_2026-10-13.csv \
#     --lib=<throwaway library> \
#     --icpc2=<norsyss.cs9>/R/00_data_icpc2.R
#
# The script needs all 3 arguments and has no defaults. It stops with a
# usage line when one is missing.
#
# --csv is a local copy of norsyss_respiratory_v1_2026-10-13.csv from the
# share. Copy it first: the script never reads the share. It holds 5 ICPC-2
# groups, national and total age. The script runs v1 and v4 with the
# arguments of norsyss.cs9:
# - v1: short_term_trend() and signal_detection_hlm() on the csfmt_rts_data_v1
#   table of each group, as the norsyss.cs9 tasks call them. The MEM fit of
#   r80_estimate_mem_thresholds_fit() in norsyss.cs9, copied here.
# - v4 tasks 1 to 3: the script runs the R blocks of the spec, marked
#   <!-- task:rules -->, <!-- task:trend -->, <!-- task:hlm --> and
#   <!-- task:mem -->, as written. Tasks 1 and 2 run after the rules block,
#   and task 3 runs alone. The script binds only their input: d, the csv rows,
#   and icpc2, the flag of each group. The checks use the ensemble x and the
#   table out of each task.
# - The compressed form, which no task stores: ens_compress_v4() of the v4
#   ensemble, a save, a read and as_ensemble_v4(), then the same steps. This
#   checks csalert, not a spec.
#
# The script first installs this working tree with R CMD INSTALL into
# the library that --lib names, puts that library first on .libPaths(), and
# loads csalert from it. It never installs into the user library. --icpc2 is
# the norsyss.cs9 file that sets the flag of each group.
#
# It exits with status 1 when one of these checks fails:
# 1. trend: v4 pinc >= 1 - alpha / 2 agrees with v1 "increasing" in >= 95% of
#    the weeks where both are not NA, pooled over the 5 groups. Both NA or
#    both not NA in >= 99% of the weeks.
# 2. HLM: v4 "high" agrees with v1 "high" in >= 98% of the eligible weeks,
#    pooled. A week is eligible when its v1 label is not "training" or
#    "forecast", and v4 has a limit. The weeks where the v4 value equals the
#    v4 limit are counted apart, because v1 uses `>` and v4 `>=`.
# 3. MEM: in each r80 season that both fit, each of the 4 v4 thresholds in
#    the table out of the MEM block is within 0.5% of the v1 fit. The tolerance covers the csv rate, which is
#    rounded to 3 decimals. The table holds the 3 fit fields of v1. In each
#    season that both fit, the season start and the season length are
#    identical to v1. The post-epidemic threshold is within 0.5% of v1. An NA
#    threshold or field in a season that both fit fails the check.
# 4. The round trip: every percentile is NA, and the table read back, its
#    measures, its summaries and its rebuilt draws are identical() to those
#    before the save. The steps on it give identical() step columns to the
#    steps on the full ensemble.
# 5. The doc: every table, partition and column name is at most 63 bytes, the
#    doc creates no index, and each table has the columns, types, NOT NULL
#    columns and unique key of the v4 output. cs9 adds the column
#    auto_last_updated_datetime, and in a partitioned table the partition
#    column icpc2grp_tag allows NULL and is not in the unique key.
# 6. The HLM write: the table out of the HLM block holds no row without a
#    limit, and one row for each row of its ensemble with a limit.
# 7. The denominator: in each group, the denominator of the trend and HLM
#    blocks, and the v1
#    denominator and rate are the columns that the spec rule names, from the
#    flag includes_influenza_covid19 of the group in norsyss.cs9. At least one
#    group has the flag FALSE, so the check sees both sides of the rule.

# ARGUMENTS ====
usage <- paste(
  "usage: Rscript data-raw/v4_norsyss_validation.R",
  "--csv=<csv> --lib=<throwaway library> --icpc2=<R/00_data_icpc2.R>"
)
cli_args <- commandArgs(trailingOnly = TRUE)
cli_arg <- function(name) {
  prefix <- paste0("--", name, "=")
  hit <- cli_args[startsWith(cli_args, prefix)]
  if (length(hit) != 1L) {
    stop("give the argument --", name, " exactly once\n", usage, call. = FALSE)
  }
  return(substring(hit, nchar(prefix) + 1L))
}
cli <- list(
  csv = cli_arg("csv"),
  lib = cli_arg("lib"),
  icpc2 = cli_arg("icpc2")
)

stopifnot(
  file.exists("DESCRIPTION"),
  read.dcf("DESCRIPTION")[, "Package"] == "csalert"
)
lib <- cli$lib
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
install_log <- file.path(dirname(lib), "install.log")
status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-docs", "--no-multiarch", "-l", shQuote(lib), "."),
  stdout = install_log,
  stderr = install_log
)
if (status != 0) {
  stop("R CMD INSTALL failed, see ", install_log, call. = FALSE)
}
.libPaths(c(lib, .libPaths()))
invisible(loadNamespace("csalert", lib.loc = lib))
stopifnot(
  normalizePath(dirname(getNamespaceInfo("csalert", "path"))) ==
    normalizePath(lib),
  identical(
    getNamespaceVersion("csalert")[["version"]],
    unname(read.dcf("DESCRIPTION")[, "Version"])
  )
)
library(data.table)
# The spec blocks call csalert functions without csalert::.
library(csalert, lib.loc = lib)

# CFG ====
CFG <- list(
  csv = cli$csv,
  doc = "data-raw/v4-norsyss-tasks.md",
  # norsyss.cs9 sets icpc2$includes_influenza_covid19 in this file. The
  # script parses it and never runs or changes it.
  flag_source = cli$icpc2,
  groups = c("covid19", "r71", "r80", "r992", "respiratory_infections"),
  id_cols = c(
    "granularity_geo",
    "location_code",
    "age",
    "sex",
    "tariffgroup_tag",
    "icpc2grp_tag"
  ),
  # norsyss.cs9: large_scale_surveillance_analyze_short_term_trends_action()
  width = 5L,
  alpha = 0.10,
  # norsyss.cs9: large_scale_surveillance_analyze_signal_detection_hlm_action()
  baseline_isoyears = 5,
  # norsyss.cs9: r80_estimate_mem_thresholds, its weeks, i.seasons and
  # exclude_season
  mem_group = "r80",
  mem_isoweeks = c(1:20, 40:52),
  mem_i_seasons = 10,
  mem_min_seasons = 2,
  mem_exclude_seasons = c("2009/2010", "2019/2020", "2020/2021", "2021/2022"),
  max_mem_rel = 0.005,
  seed = 4L,
  rate = "numerator_vs_denominator_pr100",
  # The columns that as_ensemble_v4() rebuilds, so the store leaves them out.
  rebuilt_cols = c(
    "time_series_id",
    "time_series_label",
    "time_series_internal_id"
  ),
  tables = c(
    trend = "anon_lss_short_term_trends_v4",
    hlm = "anon_lss_signals_v4",
    mem = "anon_r80_mem_v4"
  ),
  partitioned = c("trend", "hlm"),
  # cs9 adds the partition column of a partitioned table itself, and keys
  # each partition on the other key columns.
  partition_col = "icpc2grp_tag",
  # cs9 adds this column to every table.
  cs9_cols = c(auto_last_updated_datetime = "TIMESTAMP WITHOUT TIME ZONE"),
  # The longest ICPC-2 group tag in norsyss.cs9, which names a partition.
  longest_partition_tag = "respiratory_infections",
  min_trend_pct = 95,
  min_trend_na_pct = 99,
  min_hlm_pct = 98,
  max_name_bytes = 63L
)
CFG$cutoff <- 1 - CFG$alpha / 2
CFG$keys <- c(CFG$id_cols, "isoyearweek")
CFG$out_dir <- dirname(CFG$csv)

failures <- character()
check <- function(ok, label) {
  cat(sprintf("CHECK %s: %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))
  if (!isTRUE(ok)) {
    failures <<- c(failures, label)
  }
  return(invisible(isTRUE(ok)))
}
runtime <- data.table(step = character(), seconds = numeric())
timed <- function(step, expr) {
  t0 <- proc.time()[["elapsed"]]
  out <- expr
  runtime <<- rbind(
    runtime,
    data.table(step = step, seconds = proc.time()[["elapsed"]] - t0)
  )
  return(out)
}

cat(
  "csalert",
  getNamespaceVersion("csalert")[["version"]],
  "loaded from",
  normalizePath(getNamespaceInfo("csalert", "path")),
  "\n"
)
cat("libPaths:", .libPaths(), sep = "\n  ")
cat("\n")
cat(R.version.string, "\n")
cat("csv:", CFG$csv, "md5", unname(tools::md5sum(CFG$csv)), "\n")

# PART 1 -- DATA CREATION ====
if (!file.exists(CFG$csv)) {
  stop(
    "no csv at ",
    CFG$csv,
    ". Copy norsyss_respiratory_v1_2026-10-13.csv from the share first.",
    call. = FALSE
  )
}
d <- fread(CFG$csv)
d <- d[
  granularity_geo == "nation" &
    age == "total" &
    sex == "total" &
    icpc2grp_tag %in% CFG$groups
]
d[, date := as.Date(date)]
setorder(d, icpc2grp_tag, isoyearweek)
stopifnot(
  setequal(unique(d$icpc2grp_tag), CFG$groups),
  d[, uniqueN(isoyearweek) == .N, by = icpc2grp_tag]$V1
)
print(d[,
  .(weeks = .N, first = min(isoyearweek), last = max(isoyearweek)),
  keyby = icpc2grp_tag
])

# The groups whose icpc2$includes_influenza_covid19 is TRUE in norsyss.cs9.
# The flag is set by one expression in CFG$flag_source:
#   icpc2[, includes_influenza_covid19 := icpc2group_tag %in% c(...)]
# The script takes the c(...) of that expression, which holds strings only.
flag_exprs <- Filter(
  function(e) {
    return(
      is.call(e) &&
        identical(e[[1]], as.name("[")) &&
        length(e) == 4L &&
        is.call(e[[4]]) &&
        identical(e[[4]][[1]], as.name(":=")) &&
        identical(e[[4]][[2]], as.name("includes_influenza_covid19"))
    )
  },
  as.list(parse(CFG$flag_source, keep.source = FALSE, encoding = "UTF-8"))
)
stopifnot(length(flag_exprs) == 1L)
flag_rhs <- flag_exprs[[1]][[4]][[3]]
stopifnot(
  identical(flag_rhs[[1]], as.name("%in%")),
  identical(flag_rhs[[2]], as.name("icpc2group_tag")),
  identical(flag_rhs[[3]][[1]], as.name("c")),
  all(vapply(as.list(flag_rhs[[3]])[-1], is.character, logical(1)))
)
flu_groups <- eval(flag_rhs[[3]], baseenv())
cat(
  "flag source:",
  CFG$flag_source,
  "md5",
  unname(tools::md5sum(CFG$flag_source)),
  "\n"
)
cat("groups with includes_influenza_covid19 TRUE:", flu_groups, "\n")

# The denominator of each group, by the rule of the spec and of the v1 tasks.
den_rule <- data.table(icpc2grp_tag = CFG$groups)
den_rule[, includes_influenza_covid19 := icpc2grp_tag %in% flu_groups]
den_rule[,
  denominator_col := fifelse(
    includes_influenza_covid19,
    "consultations_all_n",
    "consultations_without_influenza_covid19_n"
  )
]
den_rule[,
  rate_col := fifelse(
    includes_influenza_covid19,
    "consultations_icpc2group_vs_all_pr100",
    "consultations_icpc2group_vs_without_influenza_covid19_pr100"
  )
]
cat("\n== denominator of each group, for v1 and v4\n")
print(den_rule)

# The v1 input, renamed as norsyss.cs9 renames it, with the denominator and
# the rate of den_rule.
v1_in <- rbindlist(lapply(CFG$groups, function(g) {
  z <- d[icpc2grp_tag == g]
  r <- den_rule[icpc2grp_tag == g]
  z[, `:=`(
    numerator_n = consultations_icpc2group_n,
    denominator_n = get(r$denominator_col)
  )]
  z[, (CFG$rate) := get(r$rate_col)]
  return(z)
}))

# The input of the spec blocks: the csv rows, as anon_norsyss_data holds
# them, and the flag of each group, as icpc2 of norsyss.cs9 holds it.
spec_d <- copy(d)
spec_icpc2 <- data.table(
  icpc2group_tag = CFG$groups,
  includes_influenza_covid19 = CFG$groups %in% flu_groups
)
# The R block under the marker <!-- task:<task> --> of the spec, parsed.
spec_block <- function(task) {
  L <- readLines(CFG$doc, encoding = "UTF-8", warn = FALSE)
  at <- which(L == sprintf("<!-- task:%s -->", task))
  stopifnot(length(at) == 1L, identical(L[at + 1L], "```r"))
  end <- min(which(L == "```" & seq_along(L) > at + 1L))
  return(parse(text = L[(at + 2L):(end - 1L)], keep.source = FALSE))
}
# Run the blocks of `tasks` in turn, in an environment that holds only the
# input. Its parent is the search path without the global environment, so a
# block cannot see an object of this script.
run_spec <- function(tasks) {
  e <- new.env(parent = parent.env(globalenv()))
  e$d <- copy(spec_d)
  e$icpc2 <- copy(spec_icpc2)
  for (k in tasks) {
    cat(sprintf(
      "spec block %s of %s:
",
      k,
      CFG$doc
    ))
    b <- spec_block(k)
    print(b)
    eval(b, e)
  }
  return(e)
}
cat(
  "doc:",
  CFG$doc,
  "md5",
  unname(tools::md5sum(CFG$doc)),
  "
"
)

# PART 2 -- ANALYSIS ====
## v1 trend and HLM, as norsyss.cs9 calls them ----
v1_trend <- list()
v1_hlm <- list()
for (g in CFG$groups) {
  x <- copy(v1_in[icpc2grp_tag == g])
  cstidy::set_csfmt_rts_data_v1(x)
  r <- timed(
    paste("v1 short_term_trend", g),
    csalert::short_term_trend(
      copy(x),
      numerator = "numerator_n",
      denominator = "denominator_n",
      prX = c(100),
      trend_isoyearweeks = CFG$width,
      remove_last_isoyearweeks = 0,
      forecast_isoyearweeks = 2,
      numerator_naming_prefix = "generic",
      denominator_naming_prefix = "generic",
      statistics_naming_prefix = "universal",
      remove_training_data = TRUE,
      include_decreasing = FALSE,
      alpha = CFG$alpha
    )
  )
  r <- r[numerator_forecasted_n_forecast == FALSE]
  v1_trend[[g]] <- r[, .(
    icpc2grp_tag = g,
    isoyearweek,
    v1_status = as.character(numerator_vs_denominator_trend0_34_status)
  )]

  r <- timed(
    paste("v1 signal_detection_hlm", g),
    csalert::signal_detection_hlm(
      copy(x),
      value = CFG$rate,
      baseline_isoyears = CFG$baseline_isoyears,
      remove_last_isoyearweeks = 0,
      forecast_isoyearweeks = 2,
      value_naming_prefix = "from_numerator",
      remove_training_data = TRUE
    )
  )
  r <- r[numerator_vs_denominator_forecasted_pr100_forecast == FALSE]
  v1_hlm[[g]] <- r[, .(
    icpc2grp_tag = g,
    isoyearweek,
    v1_thr = numerator_vs_denominator_baseline_predinterval_q99x5_pr100,
    v1_status = as.character(numerator_vs_denominator_pr100_status)
  )]
}
v1_trend <- rbindlist(v1_trend)
v1_hlm <- rbindlist(v1_hlm)

## v1 MEM, as norsyss.cs9 fits it ----
# A copy of r80_estimate_mem_thresholds_fit() and its helpers, on the
# national total-age r80 rate of the csv. The last season is that of
# 1 December of the isoyear of the last week, where norsyss.cs9 uses today.
r80 <- v1_in[icpc2grp_tag == CFG$mem_group]
m <- dcast.data.table(
  r80[isoweek %in% CFG$mem_isoweeks & !season %in% CFG$mem_exclude_seasons],
  seasonweek ~ season,
  value.var = CFG$rate
)
m <- m[, names(m)[vapply(m, function(v) !anyNA(v), logical(1))], with = FALSE]
m[, seasonweek := NULL]
seasons_v1 <- seq.Date(
  min(r80$date),
  as.Date(paste0(cstime::date_to_isoyear_c(max(r80$date)), "-12-01")),
  1
) |>
  cstime::date_to_season_c() |>
  unique() |>
  sort()
seasons_v1 <- seasons_v1[-c(1:5)]
el <- function(x, i, j) {
  if (length(dim(x)) != 2L || nrow(x) < i || ncol(x) < j) {
    return(NA_real_)
  }
  return(x[i, j])
}
fit_v1 <- function(model_data, ...) {
  if (ncol(model_data) < 2L) {
    return(NULL)
  }
  return(tryCatch(
    mem::memmodel(model_data, i.seasons = 10, ...),
    error = function(e) NULL
  ))
}
mem_v1 <- timed(
  "v1 MEM (norsyss.cs9 fit, r80)",
  rbindlist(lapply(seasons_v1, function(s) {
    model_data <- m[, names(m) < s, with = FALSE]
    fit <- fit_v1(model_data)
    if (is.na(el(fit$pre.post.intervals, 1, 3))) {
      fit <- fit_v1(model_data, i.method = 3)
    }
    return(data.table(
      season = s,
      v1_preepidemic = el(fit$pre.post.intervals, 1, 3),
      v1_medium = el(fit$epi.intervals, 1, 4),
      v1_high = el(fit$epi.intervals, 2, 4),
      v1_veryhigh = el(fit$epi.intervals, 3, 4),
      v1_postepidemic = el(fit$pre.post.intervals, 2, 3),
      v1_season_start = if (length(fit$mean.start) == 1L) {
        fit$mean.start
      } else {
        NA_real_
      },
      v1_season_weeks = if (length(fit$mean.length) == 1L) {
        fit$mean.length
      } else {
        NA_real_
      }
    ))
  }))
)

## v4: the ensemble of the spec rules, and its compressed form, stored ----
ens <- timed("v4 spec rules", run_spec("rules")$x)
ens <- timed(
  "v4 ens_add_rate_v4",
  csalert::ens_add_rate_v4(
    ens,
    numerator = "numerator",
    denominator = "denominator",
    per = 100,
    name = CFG$rate
  )
)
stored_table <- timed("v4 ens_compress_v4", csalert::ens_compress_v4(ens))
stored_table[, (CFG$rebuilt_cols) := NULL]

fmt <- if (requireNamespace("qs2", quietly = TRUE)) "qs2" else "rds"
store_path <- file.path(CFG$out_dir, paste0("v4_norsyss_compressed.", fmt))
cat("store format:", fmt, "at", store_path, "\n")
if (fmt == "rds") {
  cat("qs2 is not installed, so the store is .rds\n")
}
timed(
  paste("v4 save", fmt),
  if (fmt == "qs2") {
    qs2::qs_save(stored_table, store_path)
  } else {
    saveRDS(stored_table, store_path)
  }
)
read <- timed(
  paste("v4 read", fmt),
  if (fmt == "qs2") qs2::qs_read(store_path) else readRDS(store_path)
)
# A table read from a store or by DBI MUST pass through setDT() first.
setDT(read)
back <- timed(
  "v4 as_ensemble_v4",
  csalert::as_ensemble_v4(read, id_cols = CFG$id_cols)
)
pre <- csalert::as_ensemble_v4(copy(stored_table), id_cols = CFG$id_cols)

## v4 tasks 1 to 3 on the full ensemble ----
# The spec blocks, as written. The MEM block filters r80 and ISO weeks 1 to 20
# and 40 to 52 itself.
task_trend <- timed("v4 spec task 1, trend", run_spec(c("rules", "trend")))
task_hlm <- timed("v4 spec task 2, HLM", run_spec(c("rules", "hlm")))
task_mem <- timed("v4 spec task 3, MEM", run_spec("mem"))
ens_trend <- task_trend$x
ens_hlm <- task_hlm$x
mem_full <- task_mem$x
step_cols <- list(
  trend = task_trend$new_cols,
  hlm = task_hlm$new_cols,
  mem = task_mem$new_cols
)

## v4 tasks 1 to 3 on the compressed form, which no spec stores ----
cx <- timed(
  "v4 compressed: as_ensemble_v4 (n_sim = 1)",
  csalert::as_ensemble_v4(read, id_cols = CFG$id_cols, n_sim = 1L)
)
cx <- timed(
  "v4 compressed: short_term_trend_v4",
  csalert::short_term_trend_v4(
    cx,
    measure = "numerator",
    width = CFG$width,
    denominator = "denominator",
    name = CFG$rate,
    seed = CFG$seed
  )
)
cx <- timed(
  "v4 compressed: ens_add_rate_v4",
  csalert::ens_add_rate_v4(
    cx,
    numerator = "numerator",
    denominator = "denominator",
    per = 100,
    name = CFG$rate
  )
)
cx <- timed(
  "v4 compressed: signal_detection_hlm_v4",
  csalert::signal_detection_hlm_v4(
    cx,
    measure = CFG$rate,
    baseline_isoyears = CFG$baseline_isoyears
  )
)
mem_cx <- csalert::as_ensemble_v4(
  read[
    icpc2grp_tag == CFG$mem_group &
      as.integer(substr(isoyearweek, 6, 7)) %in% CFG$mem_isoweeks
  ],
  id_cols = CFG$id_cols,
  n_sim = 1L
)
mem_cx <- csalert::ens_add_rate_v4(
  mem_cx,
  numerator = "numerator",
  denominator = "denominator",
  per = 100,
  name = CFG$rate
)
mem_cx <- timed(
  "v4 compressed: mem_thresholds_v4",
  csalert::mem_thresholds_v4(
    mem_cx,
    measure = CFG$rate,
    min_seasons = CFG$mem_min_seasons,
    i.seasons = CFG$mem_i_seasons,
    exclude_seasons = CFG$mem_exclude_seasons
  )
)

# PART 3 -- OUTPUT ====
# Each table holds one row per group and one pooled row. `f` returns one row.
by_group_and_pooled <- function(z, f) {
  return(rbind(
    z[, f(.SD), keyby = icpc2grp_tag],
    cbind(data.table(icpc2grp_tag = "pooled"), f(z))
  ))
}

## The denominator ----
# The spec rule, applied to the csv apart from den_rule: all consultations
# where the flag is TRUE, and the consultations without influenza and
# COVID-19 where it is FALSE.
want <- d[, .(
  icpc2grp_tag,
  isoyearweek,
  den = as.numeric(fifelse(
    icpc2grp_tag %in% flu_groups,
    consultations_all_n,
    consultations_without_influenza_covid19_n
  )),
  rate = fifelse(
    icpc2grp_tag %in% flu_groups,
    consultations_icpc2group_vs_all_pr100,
    consultations_icpc2group_vs_without_influenza_covid19_pr100
  )
)]
got <- ens_trend$data[, .(icpc2grp_tag, isoyearweek)]
got[, v4_den := ens_trend$draws$denominator[, 1]]
got[
  ens_hlm$data[, .(
    icpc2grp_tag,
    isoyearweek,
    d = ens_hlm$draws$denominator[, 1]
  )],
  on = c("icpc2grp_tag", "isoyearweek"),
  v4_hlm_den := i.d
]
got[
  v1_in,
  on = c("icpc2grp_tag", "isoyearweek"),
  `:=`(
    v1_den = as.numeric(i.denominator_n),
    v1_rate = get(paste0("i.", CFG$rate))
  )
]
got <- got[want, on = c("icpc2grp_tag", "isoyearweek")]
den_tab <- got[,
  .(
    weeks = .N,
    v4_den_ok = all(v4_den == den & v4_hlm_den == den),
    v1_den_ok = all(v1_den == den),
    v1_rate_ok = all(v1_rate == rate | (is.na(v1_rate) & is.na(rate)))
  ),
  keyby = icpc2grp_tag
]
print(den_tab)
check(
  nrow(got) == nrow(ens_trend$data) &&
    nrow(got) == nrow(ens_hlm$data) &&
    !anyNA(got[, .(v4_den, v4_hlm_den, v1_den, den)]) &&
    isTRUE(all(den_tab$v4_den_ok & den_tab$v1_den_ok & den_tab$v1_rate_ok)) &&
    any(!CFG$groups %in% flu_groups),
  sprintf(
    "denominator: the v4 trend and HLM blocks and v1 use the denominator of the spec rule in each of the %d groups (%d with the flag FALSE: %s)",
    length(CFG$groups),
    sum(!CFG$groups %in% flu_groups),
    paste(setdiff(CFG$groups, flu_groups), collapse = ", ")
  )
)

## The trend ----
v4_trend <- ens_trend$data[, .(
  icpc2grp_tag,
  isoyearweek,
  pinc = get(paste0(CFG$rate, "_trend_pinc"))
)]
tr <- v4_trend[v1_trend, on = c("icpc2grp_tag", "isoyearweek")]
tr[, v1_inc := fifelse(is.na(v1_status), NA, v1_status == "increasing")]
tr[, v4_inc := pinc >= CFG$cutoff]
trend_tab <- by_group_and_pooled(tr, function(z) {
  both <- !is.na(z$v1_inc) & !is.na(z$v4_inc)
  return(data.table(
    weeks = nrow(z),
    both_not_na = sum(both),
    agree_pct = 100 * mean(z$v1_inc[both] == z$v4_inc[both]),
    na_agree_pct = 100 * mean(is.na(z$v1_inc) == is.na(z$v4_inc)),
    v1_increasing = sum(z$v1_inc, na.rm = TRUE),
    v4_increasing = sum(z$v4_inc, na.rm = TRUE),
    v1_only = sum(z$v1_inc[both] & !z$v4_inc[both]),
    v4_only = sum(!z$v1_inc[both] & z$v4_inc[both]),
    near_cutoff = sum(abs(z$pinc - CFG$cutoff) <= 0.01, na.rm = TRUE)
  ))
})
cat(sprintf(
  "\n== trend: v1 'increasing' against v4 pinc >= %.2f (base: v1 weeks, series x week)\n",
  CFG$cutoff
))
# Each check compares the unrounded value. Only the printed copy is rounded.
print(copy(trend_tab)[, `:=`(
  agree_pct = round(agree_pct, 2),
  na_agree_pct = round(na_agree_pct, 2)
)][])
pooled <- trend_tab[icpc2grp_tag == "pooled"]
check(
  pooled$agree_pct >= CFG$min_trend_pct,
  sprintf(
    "trend 'increasing' agreement %.2f%% >= %d%% (pooled, %d weeks)",
    pooled$agree_pct,
    CFG$min_trend_pct,
    pooled$both_not_na
  )
)
check(
  pooled$na_agree_pct >= CFG$min_trend_na_pct,
  sprintf(
    "trend NA agreement %.2f%% >= %d%% (pooled, %d weeks)",
    pooled$na_agree_pct,
    CFG$min_trend_na_pct,
    pooled$weeks
  )
)

## HLM ----
v4_hlm <- ens_hlm$data[, .(
  icpc2grp_tag,
  isoyearweek,
  v4_thr = get(paste0(CFG$rate, "_hlm_thr")),
  v4_p_high = get(paste0(CFG$rate, "_hlm_prob_high"))
)]
v4_hlm[, v4_value := ens_hlm$draws[[CFG$rate]][, 1]]
hl <- v4_hlm[v1_hlm, on = c("icpc2grp_tag", "isoyearweek")]
hl[, eligible := !v1_status %in% c("training", "forecast") & !is.na(v4_thr)]
hl[, at_limit := eligible & v4_value == v4_thr]
hl[, v1_high := v1_status == "high"]
hl[, v4_high := v4_p_high == 1]
hlm_tab <- by_group_and_pooled(hl, function(z) {
  b <- z$eligible & !z$at_limit
  return(data.table(
    weeks = nrow(z),
    eligible = sum(z$eligible),
    at_limit = sum(z$at_limit),
    at_limit_disagree = sum(z$at_limit & z$v1_high != z$v4_high),
    base = sum(b),
    agree_pct = 100 * mean(z$v1_high[b] == z$v4_high[b]),
    v1_high = sum(z$v1_high[b]),
    v4_high = sum(z$v4_high[b]),
    v1_only = sum(z$v1_high[b] & !z$v4_high[b]),
    v4_only = sum(!z$v1_high[b] & z$v4_high[b]),
    max_abs_thr_diff = signif(max(abs(z$v1_thr - z$v4_thr)[b]), 3)
  ))
})
cat(
  "\n== HLM: v1 'high' against v4 'high' (base: eligible weeks that are not at the limit)\n"
)
print(copy(hlm_tab)[, agree_pct := round(agree_pct, 2)][])
pooled <- hlm_tab[icpc2grp_tag == "pooled"]
check(
  pooled$agree_pct >= CFG$min_hlm_pct,
  sprintf(
    "HLM 'high' agreement %.2f%% >= %d%% (pooled, %d weeks; %d weeks at the limit apart)",
    pooled$agree_pct,
    CFG$min_hlm_pct,
    pooled$base,
    pooled$at_limit
  )
)

## MEM ----
thr_names <- c("preepidemic", "medium", "high", "veryhigh")
# The table out of the MEM block, as the task writes it.
v4_mem <- task_mem$out[,
  paste0(CFG$rate, "_mem_thr_", thr_names),
  with = FALSE
]
setnames(v4_mem, paste0("v4_", thr_names))
v4_mem[, season := cstime::isoyearweek_to_season_c(task_mem$out$isoyearweek)]
v4_mem <- unique(v4_mem)
stopifnot(!anyDuplicated(v4_mem$season))
mm <- merge(mem_v1, v4_mem, by = "season", all = TRUE)
for (k in thr_names) {
  mm[,
    (paste0("rel_", k)) := get(paste0("v4_", k)) / get(paste0("v1_", k)) - 1
  ]
}
# A side fits a season when one of its 4 thresholds is not NA. In a season
# that both fit, all 4 thresholds MUST be not NA on both sides, or the check
# fails: no fitted season goes unchecked.
v1_fits <- rowSums(!is.na(mm[, paste0("v1_", thr_names), with = FALSE])) > 0
v4_fits <- rowSums(!is.na(mm[, paste0("v4_", thr_names), with = FALSE])) > 0
both <- mm[v1_fits & v4_fits]
thr_complete <- !anyNA(
  both[, paste0(rep(c("v1_", "v4_"), each = 4), thr_names), with = FALSE]
)
max_rel <- max(abs(unlist(both[, paste0("rel_", thr_names), with = FALSE])))
cat(sprintf(
  "\n== MEM: v4 thresholds against the norsyss.cs9 v1 fit, %s, national, total age, ISO weeks 1-20 and 40-52\n",
  CFG$mem_group
))
# The check compares the unrounded differences. Only the printed copy is
# rounded.
both_print <- both[,
  c("season", paste0(c("v1_", "v4_", "rel_"), rep(thr_names, each = 3))),
  with = FALSE
]
for (k in paste0("rel_", thr_names)) {
  set(both_print, j = k, value = signif(both_print[[k]], 3))
}
print(both_print)
cat("seasons only v1 fits:", mm[v1_fits & !v4_fits, season], "\n")
cat("seasons only v4 fits:", mm[v4_fits & !v1_fits, season], "\n")
cat(sprintf("largest relative difference: %.3g\n", max_rel))
check(
  nrow(both) > 0 && thr_complete && max_rel <= CFG$max_mem_rel,
  sprintf(
    "MEM: the %d thresholds of the %d seasons that both fit are not NA and within %.1f%% of v1 (largest %.4g%%)",
    4L * nrow(both),
    nrow(both),
    100 * CFG$max_mem_rel,
    100 * max_rel
  )
)

# The 3 fit fields that v1 publishes: the post-epidemic threshold, and the
# season start and length.
fit_fields <- c(
  postepidemic = "thr_postepidemic",
  season_start = "season_start",
  season_weeks = "season_weeks"
)
fit_cols <- paste0(CFG$rate, "_mem_", fit_fields)
has_fields <- check(
  all(fit_cols %in% names(task_mem$out)),
  sprintf(
    "MEM: the table out of the MEM block has the 3 fit fields %s",
    paste(fit_cols, collapse = ", ")
  )
)
if (has_fields) {
  v4_fields <- task_mem$out[, fit_cols, with = FALSE]
  setnames(v4_fields, paste0("v4_", names(fit_fields)))
  v4_fields[,
    season := cstime::isoyearweek_to_season_c(task_mem$out$isoyearweek)
  ]
  v4_fields <- unique(v4_fields)
  stopifnot(!anyDuplicated(v4_fields$season))
  # Every season that both fit by their 4 thresholds, with no season
  # removed. A field that is NA on either side fails the checks below.
  mf <- merge(
    data.table(season = both$season),
    mem_v1[, c("season", paste0("v1_", names(fit_fields))), with = FALSE],
    by = "season",
    all.x = TRUE
  )
  mf <- merge(mf, v4_fields, by = "season", all.x = TRUE)
  field_cols <- paste0(rep(c("v1_", "v4_"), each = 3), names(fit_fields))
  fields_na <- mf[, rowSums(is.na(.SD)) > 0, .SDcols = field_cols]
  fields_complete <- nrow(mf) == nrow(both) && !any(fields_na)
  check(
    nrow(mf) > 0 && fields_complete,
    sprintf(
      "MEM: the 3 fit fields are not NA on either side in each of the %d seasons that both fit (%d compared; NA in: %s)",
      nrow(both),
      sum(!fields_na),
      if (any(fields_na)) {
        paste(mf$season[fields_na], collapse = ", ")
      } else {
        "none"
      }
    )
  )
  # The check compares the unrounded difference. Only the print rounds it.
  mf[, rel_postepidemic := v4_postepidemic / v1_postepidemic - 1]
  cat(sprintf(
    "
== MEM: the 3 v4 fit fields against the norsyss.cs9 v1 fit, %s, national, total age
",
    CFG$mem_group
  ))
  print(mf[, .(
    season,
    v1_postepidemic,
    v4_postepidemic,
    rel_postepidemic = signif(rel_postepidemic, 3),
    v1_season_start,
    v4_season_start,
    v1_season_weeks,
    v4_season_weeks
  )])
  max_rel_post <- max(abs(mf$rel_postepidemic))
  check(
    nrow(mf) > 0 &&
      fields_complete &&
      is.integer(mf$v4_season_start) &&
      isTRUE(all(mf$v4_season_start == mf$v1_season_start)),
    sprintf(
      "MEM: the season start is identical to v1 in each of the %d seasons that both fit",
      nrow(mf)
    )
  )
  check(
    nrow(mf) > 0 &&
      fields_complete &&
      is.integer(mf$v4_season_weeks) &&
      isTRUE(all(mf$v4_season_weeks == mf$v1_season_weeks)),
    sprintf(
      "MEM: the season length is identical to v1 in each of the %d seasons that both fit",
      nrow(mf)
    )
  )
  check(
    nrow(mf) > 0 && fields_complete && max_rel_post <= CFG$max_mem_rel,
    sprintf(
      "MEM: the post-epidemic threshold is within %.1f%% of v1 in each of the %d seasons that both fit (largest %.4g%%)",
      100 * CFG$max_mem_rel,
      nrow(mf),
      100 * max_rel_post
    )
  )
}

## The round trip ----
base_measures <- csalert:::.v4_stored_measures(names(read))
pct_cols <- unlist(lapply(base_measures, function(m) {
  return(csalert:::.v4_summary_names(m)[-1])
}))
cat("\n== round trip:", fmt, "| base measures:", base_measures, "\n")
check(
  setequal(base_measures, c("numerator", "denominator", CFG$rate)) &&
    all(vapply(
      pct_cols,
      function(v) {
        return(all(is.na(read[[v]])))
      },
      logical(1)
    )),
  sprintf(
    "round trip: every one of the %d percentile columns is NA",
    length(pct_cols)
  )
)
check(
  setequal(csalert:::.v4_measures(back), csalert:::.v4_measures(pre)) &&
    identical(names(back$data), names(pre$data)) &&
    identical(names(read), names(stored_table)) &&
    all(vapply(
      names(read),
      function(v) identical(read[[v]], stored_table[[v]]),
      logical(1)
    )) &&
    all(vapply(
      names(pre$data),
      function(v) identical(back$data[[v]], pre$data[[v]]),
      logical(1)
    )),
  "round trip: the ensemble read back has the measures and summaries of the ensemble before the save"
)
check(
  setequal(csalert:::.v4_measures(back), base_measures) &&
    all(vapply(
      base_measures,
      function(m) {
        b <- csalert:::.v4_draws(back, m)
        full <- ens$draws[[m]][, 1]
        return(
          identical(b, csalert:::.v4_draws(pre, m)) &&
            identical(b, matrix(full, nrow = length(full), ncol = back$n_sim))
        )
      },
      logical(1)
    )),
  sprintf(
    "round trip: the %d rebuilt draws of each base measure equal the one full draw",
    back$n_sim
  )
)
compare_steps <- function(a, b, v) {
  same <- vapply(v, function(k) identical(a$data[[k]], b$data[[k]]), logical(1))
  if (!all(same)) {
    cat("differ:", v[!same], "\n")
  }
  return(all(same))
}
check(
  compare_steps(cx, ens_trend, step_cols$trend) &&
    compare_steps(cx, ens_hlm, step_cols$hlm) &&
    compare_steps(mem_cx, mem_full, step_cols$mem),
  sprintf(
    "the steps on the compressed form give the %d step columns of the full ensemble",
    length(unlist(step_cols))
  )
)

## The HLM write ----
# The table out of the HLM block holds only the rows with a limit, as the
# spec says.
hlm_thr_col <- paste0(CFG$rate, "_hlm_thr")
out_tables <- list(
  trend = task_trend$out,
  hlm = task_hlm$out,
  mem = task_mem$out
)
n_limit <- sum(!is.na(ens_hlm$data[[hlm_thr_col]]))
cat(sprintf(
  "
== HLM write: %d rows of %d have a limit, %d per series
",
  n_limit,
  nrow(ens_hlm$data),
  n_limit %/% uniqueN(ens_hlm$data$time_series_id)
))
print(ens_hlm$data[,
  .(rows = .N, with_limit = sum(!is.na(get(hlm_thr_col)))),
  keyby = icpc2grp_tag
])
check(
  n_limit > 0L &&
    n_limit < nrow(ens_hlm$data) &&
    !anyNA(out_tables$hlm[[hlm_thr_col]]) &&
    nrow(out_tables$hlm) == n_limit,
  sprintf(
    "HLM write: the %d rows out of the HLM block are the %d rows with a limit, and none has no limit",
    nrow(out_tables$hlm),
    n_limit
  )
)

## The doc ----
L <- readLines(CFG$doc, encoding = "UTF-8", warn = FALSE)
opens <- which(L == "```sql")
closes <- which(L == "```")
doc <- rbindlist(lapply(opens, function(i) {
  block <- L[(i + 1L):(min(closes[closes > i]) - 1L)]
  tb <- regmatches(block, regexec("^CREATE TABLE ([^ (]+) \\($", block))
  tb <- vapply(tb[lengths(tb) == 2L], `[`, character(1), 2)
  co <- regmatches(
    block,
    regexec(
      "^  ([^ ]+) (CHARACTER VARYING|INTEGER|DOUBLE PRECISION|TIMESTAMP WITHOUT TIME ZONE)( NOT NULL)?,?$",
      block
    )
  )
  co <- co[lengths(co) == 4L]
  uq <- regmatches(block, regexec("^  UNIQUE \\((.*)\\)$", block))
  uq <- uq[lengths(uq) == 2L]
  return(data.table(
    table = tb,
    column = vapply(co, `[`, character(1), 2),
    type = vapply(co, `[`, character(1), 3),
    not_null = vapply(co, `[`, character(1), 4) != "",
    unique_key = if (length(uq)) uq[[1]][2] else NA_character_
  ))
}))
# Every name in a code span of the prose, too.
spans <- unlist(regmatches(L, gregexpr("`[a-z][a-z0-9_]*`", L)))
names_doc <- unique(c(
  doc$table,
  paste0(CFG$tables[CFG$partitioned], "_xxpxx_", CFG$longest_partition_tag),
  doc$column,
  gsub("`", "", spans)
))
bytes <- nchar(enc2utf8(names_doc), type = "bytes")
cat(sprintf(
  "\n== doc: %s | %d tables, %d columns, %d names (with the longest partition name of each partitioned table)\n",
  CFG$doc,
  uniqueN(doc$table),
  nrow(doc),
  length(names_doc)
))
print(data.table(name = names_doc, bytes = bytes)[order(-bytes)][1:5])
if (any(bytes > CFG$max_name_bytes)) {
  cat(
    "over",
    CFG$max_name_bytes,
    "bytes:",
    names_doc[bytes > CFG$max_name_bytes],
    "\n"
  )
}
check(
  length(names_doc) > 0 && all(bytes <= CFG$max_name_bytes),
  sprintf(
    "doc: every one of the %d names is at most %d bytes (longest %d)",
    length(names_doc),
    CFG$max_name_bytes,
    max(bytes)
  )
)

check(
  !any(grepl("CREATE( UNIQUE)? INDEX", L, ignore.case = TRUE)),
  "doc: no table has an index other than its unique index"
)
sql_type <- function(v) {
  return(switch(
    class(v)[1],
    character = "CHARACTER VARYING",
    integer = "INTEGER",
    numeric = "DOUBLE PRECISION",
    class(v)[1]
  ))
}
check(
  setequal(unique(doc$table), CFG$tables),
  sprintf("doc: the tables are %s", paste(CFG$tables, collapse = ", "))
)
for (k in names(CFG$tables)) {
  spec <- doc[table == CFG$tables[[k]]]
  out <- out_tables[[k]]
  # The output columns, then the columns that cs9 adds.
  cols_out <- c(names(out), names(CFG$cs9_cols))
  type_out <- vapply(
    spec$column,
    function(v) {
      if (v %in% names(CFG$cs9_cols)) {
        return(CFG$cs9_cols[[v]])
      }
      return(sql_type(out[[v]]))
    },
    character(1)
  )
  na_in_not_null <- vapply(
    spec$column[spec$not_null],
    function(v) anyNA(out[[v]]),
    logical(1)
  )
  key <- trimws(strsplit(spec$unique_key[1], ",")[[1]])
  key_want <- if (k %in% CFG$partitioned) {
    setdiff(CFG$keys, CFG$partition_col)
  } else {
    CFG$keys
  }
  missing <- setdiff(cols_out, spec$column)
  extra <- setdiff(spec$column, cols_out)
  if (length(missing) || length(extra)) {
    cat(
      k,
      "missing from the doc:",
      missing,
      "| not in the output:",
      extra,
      "\n"
    )
  }
  check(
    nrow(spec) > 0 &&
      !length(missing) &&
      !length(extra) &&
      all(type_out == spec$type) &&
      !any(na_in_not_null) &&
      setequal(key, key_want) &&
      setequal(spec$column[spec$not_null], key_want) &&
      !anyDuplicated(out[, CFG$keys, with = FALSE]),
    sprintf(
      "doc: %s has the %d columns, the types, the NOT NULL keys and the unique key of the output and cs9 (%d rows)",
      CFG$tables[[k]],
      length(cols_out),
      nrow(out)
    )
  )
}

## Runtime and the result ----
cat("\n== runtime (seconds)\n")
print(runtime[,
  .(seconds = round(sum(seconds), 2)),
  by = .(
    step = sub(
      " (covid19|r71|r80|r992|respiratory_infections)$",
      " (5 groups)",
      step
    )
  )
])
if (length(failures)) {
  cat("\nFAILED:", length(failures), "check(s)\n")
  cat(paste0("  ", failures), sep = "\n")
  quit(status = 1)
}
cat("\nALL CHECKS PASS\n")
