# Phase 2 discriminator: every reader of `as_of` takes a Date.
#
# Run it with:
#   env NOT_CRAN=true Rscript --vanilla tests/manual/phase2_as_of.R
#
# The script prints one line per check. It runs every check before it stops, so
# one run names every broken invariant. Every check that calls the package is
# wrapped, so a function that does not exist yet is a FAILED check and not an
# aborted run. It stops with a non-zero exit status if any check fails.
#
# Rscript --vanilla -f <file> segfaults on this machine (R 4.4.2, Windows).
# Pass the path as a positional argument, as above.

args <- commandArgs(trailingOnly = FALSE)
this_file <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
if (length(this_file) == 0) {
  this_file <- "tests/manual/phase2_as_of.R"
}
pkg_root <- normalizePath(
  file.path(dirname(this_file[1]), "..", ".."),
  winslash = "/"
)
pkgload::load_all(pkg_root, quiet = TRUE)

failures <- character(0)
last_error <- ""

check <- function(label, ok, detail = "") {
  if (isTRUE(ok)) {
    cat("PASS [", label, "]\n", sep = "")
  } else {
    cat("FAIL [", label, "] ", detail, "\n", sep = "")
    failures <<- c(failures, label)
  }
  return(invisible(isTRUE(ok)))
}

# An error is a FAILED check, never an aborted run. safe() returns NULL and
# parks the message in last_error.
safe <- function(expr) {
  return(tryCatch(
    expr,
    error = function(e) {
      last_error <<- conditionMessage(e)
      return(NULL)
    }
  ))
}

# mark a whole group failed when the call it depends on could not run
fail_group <- function(labels, detail) {
  for (l in labels) {
    check(l, FALSE, detail)
  }
}

ID <- c("indicator", "location", "age", "sex")
MAXD <- 28L # delay DAYS, the four weekly delay cells 0, 7, 14 and 21

# ---- the fixture -----------------------------------------------------------
# 30 reference weeks. Each is reported on four reporting Mondays: delay days 0,
# 7, 14 and 21. 2019-12-30 is the Monday of ISO week 2020-01.
n_weeks <- 30L
mondays <- as.Date("2019-12-30") + 7L * (seq_len(n_weeks) - 1L)
set.seed(3)
rows <- list()
for (w in seq_len(n_weeks)) {
  n <- stats::rpois(1, 120)
  del <- sample(0:3, n, replace = TRUE, prob = c(.4, .3, .2, .1))
  rows[[w]] <- data.table::data.table(
    isoyearweek_reference = format(mondays[w], "%G-%V"),
    reporting_date = mondays[w] + 7L * del
  )
}
ll <- data.table::rbindlist(rows)
ll <- ll[reporting_date <= mondays[n_weeks]]
tri_dt <- ll[, .(numerator = .N), by = .(isoyearweek_reference, reporting_date)]
tri_dt[, `:=`(
  indicator = "test",
  location = "nation",
  age = "total",
  sex = "total"
)]
tri <- csfmt_reporting_triangle_v3(tri_dt[], id_cols = ID)

passthrough <- function(x) {
  nowcast_passthrough_to_ensemble_v1(x, max_delay_days = MAXD)
}

# A method that CONSUMES the RNG. The seed check needs one: the package engine
# nowcast_delay_ecdf_v1 permutes its draws but reports quantiles of them. A
# quantile does not see that order, so the engine would pass the seed check
# whatever the seed did.
rng_method <- function(x) {
  base <- nowcast_passthrough_to_ensemble_v1(x, max_delay_days = MAXD)
  d <- data.table::copy(base$data)
  n <- nrow(d)
  lam <- pmax(d$original, 1)
  dr <- list()
  dr[[names(base$draws)[1]]] <- matrix(
    stats::rpois(n * 40L, rep(lam, 40L)),
    nrow = n
  )
  return(csfmt_ensemble_v3(
    d,
    id_cols = attr(x, "id_cols"),
    time_col = "isoyearweek",
    draws = dr
  ))
}

# ---- check 1: no function reads the reporting axis through the week table ----
# The invariant in machine-checkable form. `dates_by_isoyearweek` is the ISO-week
# calendar table; a reporting value looked up in it is the fault this phase
# removes.
src_files <- c(
  "R/nowcast_backtest.R",
  "R/reporting_completion.R",
  "R/nowcast_evaluate.R"
)
for (f in src_files) {
  txt <- readLines(file.path(pkg_root, f), warn = FALSE)
  hits <- grep("dates_by_isoyearweek", txt, fixed = TRUE)
  check(
    paste0("no-week-lookup/", f),
    length(hits) == 0L,
    paste0("found on line(s) ", paste(hits, collapse = ", "))
  )
}

# ---- check 2: a non-Date as_of errors, it does not answer wrongly ----------
# Measured on the pre-assertion tree, 2026-09-22. R reads
# `reporting date <= as_of` from the type of as_of, and each type fails
# differently. 18262 is a day count since 1970-01-01, so it censored to
# 2020-01-01 and reported nothing wrong. "2020-11" went through as.Date() and
# errored inside charToDate(), with a message that never named as_of. An IDate
# gave the right answer. A factor raised an "Incompatible methods" warning and
# then an unrelated error. One strict check at the boundary replaces all four.
bad_as_of <- list(
  character = "2020-11",
  numeric = 18262,
  IDate = data.table::as.IDate(mondays[10]),
  factor = factor("2020-03-02")
)
for (nm in names(bad_as_of)) {
  got <- tryCatch(
    {
      nowcast_censor(tri, bad_as_of[[nm]])
      "ACCEPTED, no error"
    },
    error = function(e) conditionMessage(e)
  )
  check(
    paste0("censor-type/", nm),
    grepl("must be a Date", got, fixed = TRUE),
    paste0("got: ", got)
  )
}

# ---- check 3: the same as_of gives the same seed, twice --------------------
seed_labels <- c(
  "seed-stability/nonempty",
  "seed-stability/same-seed-same-draws",
  "seed-stability/order-independent",
  "seed-stability/different-seed-differs"
)
seed_as_of <- mondays[c(12, 16, 20)] + 6L
P <- c(0.05, 0.5, 0.95)
run_bt <- function(ao, sd) {
  nowcast_backtest(
    tri,
    rng_method,
    as_of_weeks = ao,
    max_delay_days = MAXD,
    horizons = 1:2,
    probs = P,
    seed = sd
  )
}
bt_a <- safe(run_bt(seed_as_of, 7))
bt_b <- safe(run_bt(seed_as_of, 7))
bt_rev <- safe(run_bt(rev(seed_as_of), 7))
bt_c <- safe(run_bt(seed_as_of, 99))
if (any(vapply(list(bt_a, bt_b, bt_rev, bt_c), is.null, logical(1)))) {
  fail_group(seed_labels, paste0("backtest errored: ", last_error))
} else {
  key <- function(x) {
    y <- data.table::copy(x)
    data.table::setorder(y, as_of, reference, quantile_level)
    return(y$predicted)
  }
  check(seed_labels[1], nrow(bt_a) > 0L, "the backtest produced no rows")
  check(
    seed_labels[2],
    identical(bt_a$predicted, bt_b$predicted),
    "two identical calls produced different draws"
  )
  # the key is the DATE, not the position in the list
  check(
    seed_labels[3],
    identical(key(bt_a), key(bt_rev)),
    "reversing the as-of list changed the draws"
  )
  # the other direction: the seed must actually reach the RNG
  check(
    seed_labels[4],
    !identical(bt_a$predicted, bt_c$predicted),
    "a different seed gave identical draws, so the seed reaches nothing"
  )
}

# ---- check 4: the default as-of set is Dates, not reference strings --------
def_labels <- c(
  "default-as-of-dates/class",
  "default-as-of-dates/values",
  "default-as-of-dates/burn-in"
)
bt_def <- safe(
  nowcast_backtest(tri, passthrough, max_delay_days = MAXD, horizons = 1:2)
)
if (is.null(bt_def)) {
  fail_group(def_labels, paste0("backtest errored: ", last_error))
} else {
  check(
    def_labels[1],
    identical(class(bt_def$as_of), "Date"),
    paste0("as_of class is ", paste(class(bt_def$as_of), collapse = "/"))
  )
  seen <- unique(bt_def$as_of)
  check(
    def_labels[2],
    identical(class(seen), "Date") && all(seen %in% (mondays + 6L)),
    "the default as-of values are not reference-week end dates"
  )
  burn_in <- as.integer(ceiling(MAXD / 7))
  # compare the day numbers: cstime stores its Monday column with integer
  # storage, so identical() on the two Date objects is FALSE on storage mode
  # alone even when the dates agree
  check(
    def_labels[3],
    identical(as.numeric(min(seen)), as.numeric(mondays[burn_in + 1L] + 6L)),
    paste0("oldest as-of is ", format(min(seen)))
  )
}

# ---- check 5: the completion column count equals max_delay_days ------------
col_labels <- c(
  "delay-column-count/exactly-35",
  "delay-column-count/highest-is-34",
  "delay-column-count/tracks-the-argument"
)
rc35 <- safe(reporting_completion_v1(tri, max_delay_days = 35))
rc7 <- safe(reporting_completion_v1(tri, max_delay_days = 7))
if (is.null(rc35) || is.null(rc7)) {
  fail_group(
    col_labels,
    paste0("reporting_completion_v1 errored: ", last_error)
  )
} else {
  n_pct <- sum(grepl("^pct_delay", names(rc35)))
  n_pct7 <- sum(grepl("^pct_delay", names(rc7)))
  check(
    col_labels[1],
    n_pct == 35L,
    paste0("got ", n_pct, " pct_delay columns, expected 35")
  )
  check(
    col_labels[2],
    "pct_delay34" %in% names(rc35) && !("pct_delay35" %in% names(rc35)),
    "the highest column is not pct_delay34"
  )
  check(
    col_labels[3],
    n_pct7 == 7L,
    paste0("max_delay_days = 7 gave ", n_pct7, " pct_delay columns")
  )
}

# ---- check 6: the four owned test files run clean ---------------------------
owned <- c(
  "test-nowcast_backtest.R",
  "test-reporting_completion.R",
  "test-nowcast_evaluate.R",
  "test-nowcast_calibration.R"
)
for (tf in owned) {
  res <- safe(testthat::test_file(
    file.path(pkg_root, "tests", "testthat", tf),
    reporter = "silent",
    package = "csalert"
  ))
  if (is.null(res)) {
    check(paste0("test-clean/", tf), FALSE, paste0("errored: ", last_error))
    next
  }
  df <- as.data.frame(res)
  nw <- sum(df$warning)
  nf <- sum(df$failed)
  ne <- sum(df$error)
  check(
    paste0("test-clean/", tf),
    nw == 0L && nf == 0L && ne == 0L,
    paste0("warnings=", nw, " failed=", nf, " errors=", ne)
  )
  cat(sprintf(
    "      %-30s passed=%d warnings=%d failed=%d errors=%d skipped=%d\n",
    tf,
    sum(df$passed),
    nw,
    nf,
    ne,
    sum(df$skipped)
  ))
}

if (length(failures) > 0) {
  stop(
    "phase2 discriminator FAILED: ",
    paste(failures, collapse = ", "),
    call. = FALSE
  )
}
cat("phase2 discriminator: every check passed\n")
