# Phase 9 discriminator: a report at delay >= max_delay_days is counted in the
# last delay column, max_delay_days - 1. It is not dropped.
#
# Run it with:
#   env NOT_CRAN=true Rscript --vanilla tests/manual/phase9_fold.R
#
# Rscript --vanilla -f <file> segfaults on this machine (R 4.4.2, Windows).
# Pass the path positionally.
#
# The script prints one line per check, runs every check, and then stops with a
# non-zero exit status if any check failed. One run names every broken
# invariant.
#
# THE COUNTS ARE POWERS OF TWO. The target week carries 1, 2, 4, 8, 16 and 32
# at delays 0, 10, 34, 35, 40 and 400 days. Every subset of those counts has
# its own sum, so the value of one cell names exactly which reports it holds.
#
# CHECK 2 MOVES A DATE AFTER CONSTRUCTION. csfmt_reporting_triangle_v3()
# rejects a report before the reference Monday, so a negative delay cannot be
# built through the constructor. The check builds a valid triangle, then sets
# one reporting date to the Sunday before its reference week.
#
# CHECK 8 PINS THE REPLAY BOUNDARY. A fold must only see the reports that were
# available on the replay's as-of date. nowcast_censor() drops every report
# after that date before the matrix is built, so the delay-40 report must not
# reach column "34" of a replay as of delay day 39.
#
# CHECK 9 PINS THE DEFAULT AS-OF SET of nowcast_backtest(). The fold puts a
# week whose only reports are late on the matrix axis. The default as-of set
# MUST still be HEAD's, so a bulk load of old weeks adds no replay dates.

args <- commandArgs(trailingOnly = FALSE)
this_file <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
if (length(this_file) == 0) {
  this_file <- "tests/manual/phase9_fold.R"
}
pkg_root <- normalizePath(
  file.path(dirname(this_file[1]), "..", ".."),
  winslash = "/"
)
pkgload::load_all(pkg_root, quiet = TRUE)

# An Rd example or a test that plots would otherwise write Rplots.pdf into the
# working directory.
grDevices::pdf(NULL)

# ---- provenance: which csalert this run measures ---------------------------
src_fold <- file.path(pkg_root, "R", "csfmt_reporting_triangle_v3.R")
src_censor <- file.path(pkg_root, "R", "nowcast_backtest.R")
# width.cutoff = 500 keeps each statement on one line, so the grep below shows
# the whole fold and the whole filter.
body_lines <- deparse(body(reporting_triangle_matrix), width.cutoff = 500L)
cat(
  "csalert namespace path: ",
  getNamespaceInfo("csalert", "path"),
  "\n",
  sep = ""
)
cat("csalert version:        ", getNamespaceVersion("csalert"), "\n", sep = "")
cat(
  "loaded by pkgload:      ",
  pkgload::is_dev_package("csalert"),
  "\n",
  sep = ""
)
cat("md5 ", src_fold, ": ", unname(tools::md5sum(src_fold)), "\n", sep = "")
cat("md5 ", src_censor, ": ", unname(tools::md5sum(src_censor)), "\n", sep = "")
cat("loaded delay lines in reporting_triangle_matrix():\n")
cat(
  paste0("  ", trimws(grep("\\.delay (>|<)", body_lines, value = TRUE))),
  sep = "\n"
)
cat("\n")

failures <- character(0)

check <- function(label, ok, detail = "") {
  if (isTRUE(ok)) {
    cat("PASS [", label, "] ", detail, "\n", sep = "")
  } else {
    cat("FAIL [", label, "] ", detail, "\n", sep = "")
    failures <<- c(failures, label)
  }
}

# ---- the synthetic triangle ------------------------------------------------
ID <- c("indicator", "location", "age", "sex")
MAXD <- 35L
cal <- cstime::dates_by_isoyearweek
TARGET <- "2023-01"
target_monday <- as.Date(cal$mon[match(TARGET, cal$isoyearweek)])
late <- data.table::data.table(
  delay = c(0L, 10L, 34L, 35L, 40L, 400L),
  n = c(1, 2, 4, 8, 16, 32)
)
FULL_TOTAL <- sum(late$n) # 63
COL34_WANT <- sum(late$n[late$delay >= MAXD - 1L]) # 4 + 8 + 16 + 32 = 60
as_of_full <- target_monday + max(late$delay)

# Background: every other reference week from 2022-45 up to the as-of week,
# reported 3 and 10 days after its Monday. It gives the engine a settled pool.
i1 <- match("2022-45", cal$isoyearweek)
i2 <- max(which(as.Date(cal$mon) <= as_of_full))
bg_idx <- setdiff(i1:i2, match(TARGET, cal$isoyearweek))
bg <- data.table::data.table(
  isoyearweek_reference = rep(cal$isoyearweek[bg_idx], each = 2L),
  reporting_date = rep(as.Date(cal$mon[bg_idx]), each = 2L) +
    rep(c(3L, 10L), length(bg_idx)),
  numerator = rep(c(10, 5), length(bg_idx))
)
bg <- bg[bg$reporting_date <= as_of_full]
tgt <- data.table::data.table(
  isoyearweek_reference = TARGET,
  reporting_date = target_monday + late$delay,
  numerator = late$n
)
raw <- data.table::rbindlist(list(tgt, bg))
raw[, `:=`(indicator = "x", location = "nation", age = "total", sex = "total")]

tri <- csfmt_reporting_triangle_v3(raw, id_cols = ID)
rt <- reporting_triangle_matrix(tri, max_delay_days = MAXD)
m <- rt[[1]]$mat
refs <- rt[[1]]$reference
row_t <- match(TARGET, refs)

# ---- CHECK 1: conservation -------------------------------------------------
# Every reference week's row sum equals the sum of its reports at a
# non-negative delay, and column "34" holds the delay-34, 35, 40 and 400 reports.
week_total <- raw[, list(total = sum(numerator)), by = "isoyearweek_reference"]
got <- unname(rowSums(m))[match(week_total$isoyearweek_reference, refs)]
n_mismatch <- sum(is.na(got) | got != week_total$total)
t_rowsum <- unname(rowSums(m)[row_t])
t_col34 <- unname(m[row_t, "34"])
check(
  "CHECK 1 conservation",
  length(rt) == 1L &&
    !is.na(row_t) &&
    n_mismatch == 0L &&
    sum(m) == sum(raw$numerator) &&
    t_rowsum == FULL_TOTAL &&
    t_col34 == COL34_WANT &&
    unname(m[row_t, "0"]) == 1 &&
    unname(m[row_t, "10"]) == 2,
  paste0(
    "target ",
    TARGET,
    ": rowSums=",
    t_rowsum,
    " want=",
    FULL_TOTAL,
    " lost=",
    FULL_TOTAL - t_rowsum,
    " col34=",
    t_col34,
    " want=",
    COL34_WANT,
    " | weeks=",
    nrow(week_total),
    " weeks_mismatched=",
    n_mismatch,
    " | matrix_total=",
    sum(m),
    " nonneg_input_total=",
    sum(raw$numerator)
  )
)

# ---- CHECK 2: a negative delay stays out -----------------------------------
NEG_WEEK <- "2023-02"
neg_monday <- as.Date(cal$mon[match(NEG_WEEK, cal$isoyearweek)])
NEG_N <- 1000
raw_neg <- data.table::rbindlist(list(
  raw,
  data.table::data.table(
    isoyearweek_reference = NEG_WEEK,
    reporting_date = neg_monday,
    numerator = NEG_N,
    indicator = "x",
    location = "nation",
    age = "total",
    sex = "total"
  )
))
tri_neg <- csfmt_reporting_triangle_v3(raw_neg, id_cols = ID)
i_neg <- which(tri_neg$numerator == NEG_N)
data.table::set(
  tri_neg,
  i = i_neg,
  j = "reporting_date",
  value = neg_monday - 1L
)
neg_delay <- as.integer(tri_neg$reporting_date[i_neg] - neg_monday)
# The negative-delay report MUST change nothing: the matrix equals the one built
# without it, cell for cell. That comparison does not depend on CHECK 1.
rt_neg <- reporting_triangle_matrix(tri_neg, max_delay_days = MAXD)[[1]]
row_n <- match(NEG_WEEK, rt_neg$reference)
neg_week_want <- sum(raw$numerator[raw$isoyearweek_reference == NEG_WEEK])
neg_week_got <- unname(rowSums(rt_neg$mat)[row_n])
check(
  "CHECK 2 negative-delay-dropped",
  length(i_neg) == 1L &&
    identical(neg_delay, -1L) &&
    !is.na(row_n) &&
    identical(rt_neg$reference, refs) &&
    identical(rt_neg$mat, m) &&
    max(rt_neg$mat) < NEG_N,
  paste0(
    "fixture delay=",
    paste(neg_delay, collapse = ","),
    " | week ",
    NEG_WEEK,
    ": rowSums=",
    neg_week_got,
    " want=",
    neg_week_want,
    " | matrix identical to the one without the report=",
    identical(rt_neg$mat, m),
    " | matrix_total=",
    sum(rt_neg$mat),
    " without=",
    sum(m),
    " | max_cell=",
    max(rt_neg$mat)
  )
)

# ---- CHECK 3: the delay columns are unchanged ------------------------------
check(
  "CHECK 3 columns-unchanged",
  identical(colnames(m), as.character(0:(MAXD - 1L))) &&
    identical(colnames(rt_neg$mat), as.character(0:(MAXD - 1L))),
  paste0(
    "ncol=",
    ncol(m),
    " first=",
    colnames(m)[1],
    " last=",
    colnames(m)[ncol(m)]
  )
)

# ---- CHECK 4: the published count ------------------------------------------
# `original` is the observed count the ensemble publishes. The target week is
# settled, so its draws are degenerate at the same number.
set.seed(1)
ens <- nowcast_delay_ecdf_v1(tri, max_delay_days = MAXD, n_sim = 50)
e_row <- which(ens$data$isoyearweek == TARGET)
e_orig <- ens$data$original[e_row]
e_draws <- ens$draws$numerator_nowcasted[e_row, ]
pt <- nowcast_passthrough_to_ensemble_v1(tri, max_delay_days = MAXD)
p_orig <- pt$data$original[pt$data$isoyearweek == TARGET]
age_t <- as.integer(attr(tri, "as_of") - target_monday)
check(
  "CHECK 4 published-count",
  length(e_row) == 1L &&
    age_t >= MAXD - 1L &&
    e_orig == FULL_TOTAL &&
    all(e_draws == FULL_TOTAL) &&
    length(p_orig) == 1L &&
    p_orig == FULL_TOTAL,
  paste0(
    "target ",
    TARGET,
    " age_days=",
    age_t,
    " | delay_ecdf original=",
    paste(e_orig, collapse = ","),
    " draws=",
    paste(unique(e_draws), collapse = ","),
    " | passthrough original=",
    paste(p_orig, collapse = ","),
    " | want=",
    FULL_TOTAL
  )
)

# ---- CHECK 7: version ------------------------------------------------------
desc_ver <- unname(read.dcf(
  file.path(pkg_root, "DESCRIPTION"),
  fields = "Version"
)[1, 1])
news_1 <- readLines(file.path(pkg_root, "NEWS.md"), n = 1L, warn = FALSE)
ns_ver <- as.character(getNamespaceVersion("csalert"))
check(
  "CHECK 7 version",
  identical(desc_ver, "2026.9.23") &&
    identical(news_1, "# Version 2026.9.23") &&
    identical(ns_ver, "2026.9.23"),
  paste0(
    "DESCRIPTION=",
    desc_ver,
    " | NEWS.md line 1='",
    news_1,
    "' | loaded namespace=",
    ns_ver
  )
)

# ---- CHECK 8: no leakage into a replay -------------------------------------
# As of delay day 39 the delay-34 and delay-35 reports are in, and the delay-40
# and delay-400 reports are not. Column "34" must hold 4 + 8 = 12. Measured two
# ways: the censor composed by hand, and the matrix a method actually receives
# inside nowcast_backtest().
as_of_c <- target_monday + 39L
C34_WANT <- sum(late$n[late$delay >= MAXD - 1L & late$delay <= 39L])
C_TOTAL <- sum(late$n[late$delay <= 39L])
cens <- nowcast_censor(tri, as_of_c)
rc <- reporting_triangle_matrix(cens, MAXD)[[1]]
c34 <- unname(rc$mat[match(TARGET, rc$reference), "34"])
c_row <- unname(rowSums(rc$mat)[match(TARGET, rc$reference)])
seen <- NULL
capture_method <- function(x) {
  seen <<- reporting_triangle_matrix(x, MAXD)[[1]]
  return(nowcast_passthrough_to_ensemble_v1(x, max_delay_days = MAXD))
}
bt <- nowcast_backtest(
  tri,
  capture_method,
  as_of_weeks = as_of_c,
  max_delay_days = MAXD,
  horizons = 0:10,
  probs = 0.5
)
bt34 <- if (is.null(seen)) {
  NA_real_
} else {
  unname(seen$mat[match(TARGET, seen$reference), "34"])
}
check(
  "CHECK 8 no-replay-leakage",
  isTRUE(attr(cens, "as_of") <= as_of_c) &&
    isTRUE(c34 == C34_WANT) &&
    isTRUE(c_row == C_TOTAL) &&
    isTRUE(bt34 == C34_WANT),
  paste0(
    "as_of=",
    format(as_of_c),
    " censored as_of=",
    format(attr(cens, "as_of")),
    " | censor+matrix col34=",
    c34,
    " rowSums=",
    c_row,
    " | inside nowcast_backtest col34=",
    bt34,
    " | want col34=",
    C34_WANT,
    " rowSums=",
    C_TOTAL
  )
)

# ---- CHECK 9: the default as-of set of nowcast_backtest() ------------------
# A bulk load: weeks 2023-01 to 2023-20 are reported once, all on 2024-02-06,
# 400 days after the first Monday. The 20 weeks after the load week report
# normally, at delays 3 and 10. The fold puts the old weeks on the matrix axis.
# The default as-of set MUST still start where HEAD (2dfed42) started it: at the
# first week with a report at delay 0 to max_delay_days - 1. Measured on HEAD
# on 2026-09-23: 15 method calls, 0 warnings, 30 rows, as-of dates 2024-03-24
# to 2024-06-30 every 7 days. With the fold and HEAD's default code instead:
# 52 "nothing reported" warnings and 40 rows.
HEAD_ASOF <- seq(as.Date("2024-03-24"), as.Date("2024-06-30"), by = 7)
bl_i0 <- match("2023-01", cal$isoyearweek)
bl_old <- bl_i0 + 0:19
bl_load <- as.Date(cal$mon[bl_i0]) + 400L
bl_new <- max(which(as.Date(cal$mon) <= bl_load)) + 1:20
bl_raw <- data.table::rbindlist(list(
  data.table::data.table(
    isoyearweek_reference = cal$isoyearweek[bl_old],
    reporting_date = bl_load,
    numerator = 20
  ),
  data.table::data.table(
    isoyearweek_reference = rep(cal$isoyearweek[bl_new], each = 2L),
    reporting_date = rep(as.Date(cal$mon[bl_new]), each = 2L) + c(3L, 10L),
    numerator = c(15, 5)
  )
))
bl_raw <- bl_raw[bl_raw$reporting_date <= as.Date(cal$mon[max(bl_new)]) + 6L]
bl_raw[, `:=`(indicator = "x", location = "n", age = "total", sex = "total")]
bl_tri <- csfmt_reporting_triangle_v3(bl_raw, id_cols = ID)
bl_calls <- 0L
bl_warn <- character(0)
bl_bt <- withCallingHandlers(
  nowcast_backtest(
    bl_tri,
    function(x) {
      bl_calls <<- bl_calls + 1L
      return(nowcast_passthrough_to_ensemble_v1(x, max_delay_days = MAXD))
    },
    max_delay_days = MAXD,
    horizons = 0:1,
    probs = 0.5
  ),
  warning = function(w) {
    bl_warn <<- c(bl_warn, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
bl_asof <- sort(unique(bl_bt$as_of))
# Compare the dates as text. The as-of dates are built from the calendar's
# integer-stored Dates, and seq() makes double-stored ones. identical() on the
# Dates themselves is FALSE for the same days, which made this check unable to
# pass when it was first run.
check(
  "CHECK 9 default-as-of-set",
  bl_calls == length(HEAD_ASOF) &&
    length(bl_warn) == 0L &&
    nrow(bl_bt) == 30L &&
    identical(format(bl_asof), format(HEAD_ASOF)),
  paste0(
    "method_calls=",
    bl_calls,
    " warnings=",
    length(bl_warn),
    " rows=",
    nrow(bl_bt),
    " as_of_dates=",
    length(bl_asof),
    " first=",
    format(bl_asof[1]),
    " last=",
    format(bl_asof[length(bl_asof)]),
    " | HEAD: method_calls=15 warnings=0 rows=30 as_of_dates=15 first=2024-03-24",
    " last=2024-06-30"
  )
)

# ---- CHECK 6, part 1: the Rd examples under warnPartialMatchArgs -----------
# The validate_ensemble() example calls try() on a bad ensemble on purpose. try()
# writes "Error : draws[['numerator_nowcasted']] has 2 rows" to stderr, and the
# example still runs to its end, so it is not counted as an example error.
rd_files <- list.files(
  file.path(pkg_root, "man"),
  pattern = "\\.Rd$",
  full.names = TRUE
)
ex_errors <- character(0)
ex_warn <- character(0)
n_with_examples <- 0L
ex_opt <- options(warnPartialMatchArgs = TRUE)
for (f in rd_files) {
  tmp <- tempfile(fileext = ".R")
  tools::Rd2ex(f, out = tmp)
  if (!file.exists(tmp) || length(readLines(tmp, warn = FALSE)) == 0L) {
    next
  }
  n_with_examples <- n_with_examples + 1L
  env <- new.env(parent = globalenv())
  res <- withCallingHandlers(
    tryCatch(
      {
        utils::capture.output(suppressMessages(source(
          tmp,
          local = env,
          echo = FALSE
        )))
        NULL
      },
      error = function(e) conditionMessage(e)
    ),
    warning = function(w) {
      ex_warn <<- c(ex_warn, paste0(basename(f), ": ", conditionMessage(w)))
      invokeRestart("muffleWarning")
    }
  )
  if (!is.null(res)) {
    ex_errors <- c(ex_errors, paste0(basename(f), ": ", res))
  }
  unlink(tmp)
}
options(ex_opt)
ex_partial <- grep(
  "partial argument match",
  ex_warn,
  fixed = TRUE,
  value = TRUE
)

# ---- CHECK 5: the suite ----------------------------------------------------
suite <- testthat::test_local(
  pkg_root,
  reporter = "silent",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
sdf <- as.data.frame(suite)
failed_labels <- unique(sdf$test[sdf$failed > 0 | sdf$error])
check(
  "CHECK 5 suite",
  sum(sdf$failed) == 0L && sum(sdf$error) == 0L,
  paste0(
    "tests=",
    nrow(sdf),
    " failed=",
    sum(sdf$failed),
    " errors=",
    sum(sdf$error),
    " warnings=",
    sum(sdf$warning),
    " skipped=",
    sum(sdf$skipped),
    if (length(failed_labels)) {
      paste0(" :: ", paste(failed_labels, collapse = " | "))
    } else {
      ""
    }
  )
)

# ---- CHECK 6, part 2: the suite under warnPartialMatchArgs -----------------
old_opt <- options(warnPartialMatchArgs = TRUE)
suite_pm <- testthat::test_local(
  pkg_root,
  reporter = "silent",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
options(old_opt)
pdf_pm <- as.data.frame(suite_pm)
pm_msgs <- character(0)
for (r in suite_pm) {
  for (k in r$results) {
    if (inherits(k, "expectation_warning")) {
      pm_msgs <- c(pm_msgs, conditionMessage(k))
    }
  }
}
n_pm_suite <- sum(pdf_pm$warning)
check(
  "CHECK 6 partial-matching",
  n_pm_suite == 0L && length(ex_warn) == 0L && length(ex_errors) == 0L,
  paste0(
    "suite_tests=",
    nrow(pdf_pm),
    " suite_warnings=",
    n_pm_suite,
    " rd_files=",
    length(rd_files),
    " rd_examples=",
    n_with_examples,
    " example_warnings=",
    length(ex_warn),
    " (partial_match=",
    length(ex_partial),
    ")",
    " example_errors=",
    length(ex_errors),
    if (length(pm_msgs)) {
      paste0(" :: suite ", paste(unique(pm_msgs), collapse = " | "))
    } else {
      ""
    },
    if (length(ex_warn)) {
      paste0(" :: examples ", paste(unique(ex_warn), collapse = " | "))
    } else {
      ""
    },
    if (length(ex_errors)) {
      paste0(" :: example errors ", paste(ex_errors, collapse = " | "))
    } else {
      ""
    }
  )
)

grDevices::dev.off()

cat("\n---- phase9 fold summary ----\n")
cat("failed checks: ", length(failures), "\n", sep = "")
if (length(failures) > 0) {
  stop(
    "phase9 fold FAILED: ",
    paste(failures, collapse = "; "),
    call. = FALSE
  )
}
cat("phase9 fold PASSED\n")
