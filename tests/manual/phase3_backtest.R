# Phase 3 discriminator: nowcast_delay_ecdf_v1 completes incomplete reference
# weeks from a daily delay ECDF, and beats the observed count at every horizon.
#
# Run it with:
#   env NOT_CRAN=true Rscript --vanilla tests/manual/phase3_backtest.R
#
# Rscript --vanilla -f <file> segfaults on this machine (R 4.4.2, Windows).
# `-f` is an R front-end flag, not an Rscript flag. Pass the path positionally.
#
# The script prints one line per check and the full per-horizon table, then
# stops with a non-zero exit status if any check failed. It runs every check
# before it stops, so one run names every broken invariant.
#
# THE DATA ARE SIMULATED. The series this engine was measured on, s19_hosp_sari,
# lives on a hospital share this repository cannot reach. So the delay curve
# here is chosen, not fitted: a discretised gamma(shape = 3, rate = 0.3) over
# delay days 0 to 34. It reaches about 6% of a week by day 2, 58% by day 9 and
# 89% by day 16, which is the SARI shape. The checks below are structural, or
# relative to a baseline the script computes. They are not the measured
# percentages of that series.
#
# THE WEEKLY VOLUME IS ALSO A CHOICE, and it is a choice about POWER. At delay
# day 30 about 0.3% of a week is still missing. On a 100-case week that is one
# third of a case, so the estimate and the observed-only baseline sit within one
# count of each other and check 5 becomes a coin flip. About 1200 cases a week
# keeps the horizon-4 comparison decided by the model rather than by rounding.

args <- commandArgs(trailingOnly = FALSE)
this_file <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
if (length(this_file) == 0) {
  this_file <- "tests/manual/phase3_backtest.R"
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
    cat("PASS [", label, "] ", detail, "\n", sep = "")
  } else {
    cat("FAIL [", label, "] ", detail, "\n", sep = "")
    failures <<- c(failures, label)
  }
  return(invisible(isTRUE(ok)))
}

# An error is a FAILED check, never an aborted run.
safe <- function(expr) {
  return(tryCatch(
    expr,
    error = function(e) {
      last_error <<- conditionMessage(e)
      return(NULL)
    }
  ))
}

MAXD <- 35L # delay DAYS: delay day 0 to 34
WINDOW <- 26L # delay_window, in WEEKS
# 2001, not a round number: stats::quantile type 7 reads p at position
# (n - 1) * p + 1, which is a whole number for both 0.05 and 0.95 only when
# n - 1 is a multiple of 20. CHECK 9 then tests an exact identity.
N_SIM <- 2001L
N_WEEKS <- 65L # simulated reference weeks
N_REPLAY <- 30L # replayed as-of dates, on weeks 31 to 60
LAST_REPLAY_WEEK <- 60L
ID <- c("indicator", "location", "age", "sex")
CAL <- cstime::dates_by_isoyearweek

# ---- the simulated triangle ------------------------------------------------
# One case lands on reference week w and delay day d. The delay distribution is
# the same every week, so the pooled ECDF is the right estimator and any bias
# the checks find comes from the code, not from the generator.
DELAY_W <- stats::dgamma(seq(0, MAXD - 1L) + 0.5, shape = 3, rate = 0.3)
DELAY_W <- DELAY_W / sum(DELAY_W)

sim_counts <- function(n_weeks, seed) {
  set.seed(seed)
  lambda <- 1200 * (1 + 0.35 * sin(2 * pi * (seq_len(n_weeks) - 8L) / 52))
  n_week <- stats::rpois(n_weeks, lambda)
  m <- matrix(0L, n_weeks, MAXD)
  for (w in seq_len(n_weeks)) {
    m[w, ] <- as.integer(stats::rmultinom(1, n_week[w], DELAY_W))
  }
  return(m)
}

sim_rows <- function(counts, mondays, refs, truncate_at = NULL) {
  rows <- list()
  for (w in seq_len(nrow(counts))) {
    keep <- counts[w, ] > 0L
    rows[[w]] <- data.table::data.table(
      isoyearweek_reference = refs[w],
      reporting_date = mondays[w] + (seq_len(MAXD) - 1L)[keep],
      numerator = counts[w, keep],
      indicator = "sim",
      location = "nation",
      age = "total",
      sex = "total"
    )
  }
  out <- data.table::rbindlist(rows)
  if (!is.null(truncate_at)) {
    out <- out[out$reporting_date <= truncate_at]
  }
  return(out[])
}

MONDAYS <- as.Date(CAL$mon[match("2023-01", CAL$isoyearweek)]) +
  7L * (seq_len(N_WEEKS) - 1L)
REFS <- CAL$isoyearweek[match(MONDAYS, as.Date(CAL$mon))]
COUNTS <- sim_counts(N_WEEKS, seed = 20260922L)
RAW <- sim_rows(COUNTS, MONDAYS, REFS)
TRI <- csfmt_reporting_triangle_v3(RAW, id_cols = ID)

# cumulative counts by delay day, straight from the generator. Every
# observed-so-far below is read from here, so the baseline in check 5 and the
# floor in check 4 never come from the engine's own output.
CUM <- t(apply(COUNTS, 1, cumsum))

# ---- setup assertions ------------------------------------------------------
# These are not the ten checks. They say the fixture is the fixture I meant.
check(
  "SETUP reference weeks start on their own Monday",
  identical(csalert:::isoyearweek_week_start(REFS), MONDAYS)
)
check(
  "SETUP wednesday rule anchored (1970-01-01 was a Thursday)",
  as.integer(as.Date("2024-01-03")) %% 7L == 6L
)

# The Wednesdays of reference weeks 31 to 60. The triangle runs 5 weeks past the
# last replay, so every reference week the replay scores has since settled and
# carries a truth. A triangle that ends on the last replay week does not: its
# newest weeks are still arriving.
AS_OF <- MONDAYS[(LAST_REPLAY_WEEK - N_REPLAY + 1L):LAST_REPLAY_WEEK] + 2L

# ---- the replay ------------------------------------------------------------
recorded_max_delay <- integer(0)
method <- function(x) {
  md <- MAXD
  recorded_max_delay <<- c(recorded_max_delay, md)
  return(nowcast_delay_ecdf_v1(
    x,
    max_delay_days = md,
    n_sim = N_SIM,
    delay_window = WINDOW
  ))
}

warned <- character(0)
bt <- withCallingHandlers(
  safe(nowcast_backtest(
    TRI,
    method,
    as_of_weeks = AS_OF,
    max_delay_days = MAXD,
    horizons = 0:70,
    probs = c(0.05, 0.5, 0.95),
    seed = 1L
  )),
  warning = function(w) {
    warned <<- c(warned, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
check(
  "SETUP replay ran without a demoted method error",
  !is.null(bt) && nrow(bt) > 0L && length(warned) == 0L,
  paste0("warnings=", length(warned), " ", last_error)
)
if (is.null(bt) || !nrow(bt)) {
  stop("phase3 discriminator: the replay produced nothing", call. = FALSE)
}

TRUTH <- nowcast_truth(TRI, MAXD)

# observed-so-far for every (reference week, as-of) pair the replay produced
wk <- match(bt$reference, REFS)
age <- as.integer(bt$as_of - MONDAYS[wk])
bt$observed <- CUM[cbind(wk, pmin(age + 1L, MAXD))]
bt$truth <- TRUTH$truth[match(bt$reference, TRUTH$reference)]
bt$d_observed <- age

scored <- unique(bt$reference)
check(
  "SETUP nowcast_truth matches the generator on every scored reference week",
  !anyNA(bt$truth) &&
    isTRUE(all.equal(
      as.numeric(TRUTH$truth[match(scored, TRUTH$reference)]),
      as.numeric(rowSums(COUNTS)[match(scored, REFS)])
    )),
  paste0("scored weeks=", length(scored), " truth rows=", nrow(TRUTH))
)

# ---- CHECK 1: thirty distinct replay dates, all Wednesdays -----------------
dates <- sort(unique(bt$as_of))
check(
  "CHECK 1 thirty-distinct-wednesday-replays",
  length(dates) == N_REPLAY && all(as.integer(dates) %% 7L == 6L),
  paste0(
    "n=",
    length(dates),
    " first=",
    format(min(dates)),
    " last=",
    format(max(dates)),
    " wednesdays=",
    sum(as.integer(dates) %% 7L == 6L)
  )
)

# ---- CHECK 2: max_delay_days is 35 at every engine call --------------------
check(
  "CHECK 2 max-delay-days-35-at-every-call",
  length(recorded_max_delay) == N_REPLAY && all(recorded_max_delay == 35L),
  paste0(
    "calls=",
    length(recorded_max_delay),
    " distinct=",
    paste(unique(recorded_max_delay), collapse = ",")
  )
)

# ---- CHECK 3: the ECDF is an ECDF ------------------------------------------
# Rebuild, per replay, the pool the engine built, with the engine's own helper.
pool_sizes <- integer(0)
mono <- logical(0)
unit <- logical(0)
width <- integer(0)
cens_as_of <- as.Date(character(0))
for (i in seq_along(AS_OF)) {
  cens <- safe(nowcast_censor(TRI, AS_OF[i]))
  if (is.null(cens)) {
    next
  }
  rts <- reporting_triangle_matrix(cens, MAXD)[[1]]
  pool <- csalert:::.delay_pool(
    rts$mat,
    rts$reference,
    attr(cens, "as_of"),
    MAXD,
    WINDOW
  )
  pool_sizes <- c(pool_sizes, length(pool$train))
  p <- pool$p
  mono <- c(mono, !is.null(p) && all(diff(p) >= 0))
  unit <- c(unit, !is.null(p) && p[length(p)] == 1)
  width <- c(width, if (is.null(p)) 0L else length(p))
  cens_as_of <- c(cens_as_of, attr(cens, "as_of"))
}
check(
  "SETUP the censored as-of is the replay Wednesday itself",
  length(cens_as_of) == length(AS_OF) && all(cens_as_of == AS_OF),
  paste0("matched=", sum(cens_as_of == AS_OF), "/", length(AS_OF))
)
check(
  "CHECK 3a ecdf-non-decreasing",
  length(mono) == N_REPLAY && all(mono),
  paste0("replays=", length(mono), " non_decreasing=", sum(mono))
)
check(
  "CHECK 3b ecdf-reaches-one-at-max-delay",
  length(unit) == N_REPLAY && all(unit) && all(width == MAXD),
  paste0(
    "p(34)==1 on ",
    sum(unit),
    " replays, widths=",
    paste(unique(width), collapse = ",")
  )
)
cat(
  "      settled pool size per replay: min=",
  min(c(pool_sizes, NA_integer_), na.rm = TRUE),
  " median=",
  stats::median(pool_sizes),
  " max=",
  max(c(pool_sizes, NA_integer_), na.rm = TRUE),
  "\n",
  sep = ""
)

# ---- CHECK 4: never below the observed count -------------------------------
below <- which(bt$predicted < bt$observed - 1e-9)
check(
  "CHECK 4 nowcast-never-below-observed",
  length(below) == 0L,
  paste0(
    "rows=",
    nrow(bt),
    " (every replayed week x quantile, not sampled) below=",
    length(below)
  )
)

# ---- the per-horizon table -------------------------------------------------
w5 <- data.table::dcast(
  bt[bt$horizon <= 4L],
  reference + as_of + horizon + observed + truth + d_observed ~ quantile_level,
  value.var = "predicted"
)
data.table::setnames(w5, c("0.05", "0.5", "0.95"), c("q05", "q50", "q95"))
w5$err <- (w5$q50 - w5$truth) / w5$truth
w5$base_err <- (w5$observed - w5$truth) / w5$truth
w5$covered <- w5$truth >= w5$q05 & w5$truth <= w5$q95

tab <- data.frame(
  h = sort(unique(w5$horizon)),
  stringsAsFactors = FALSE
)
pull <- function(h, f) {
  return(f(w5[w5$horizon == h]))
}
tab$d_obs <- vapply(tab$h, function(h) pull(h, function(z) z$d_observed[1]), 0L)
tab$n <- vapply(tab$h, function(h) pull(h, nrow), 0L)
tab$signed_pct <- vapply(
  tab$h,
  function(h) 100 * pull(h, function(z) stats::median(z$err)),
  0
)
tab$abs_pct <- vapply(
  tab$h,
  function(h) 100 * pull(h, function(z) stats::median(abs(z$err))),
  0
)
tab$baseline_abs_pct <- vapply(
  tab$h,
  function(h) 100 * pull(h, function(z) stats::median(abs(z$base_err))),
  0
)
tab$coverage90 <- vapply(
  tab$h,
  function(h) pull(h, function(z) mean(z$covered)),
  0
)

cat("\n---- per-horizon replay table (simulated series) ----\n")
print(
  data.frame(
    h = tab$h,
    d_obs = tab$d_obs,
    n = tab$n,
    signed = paste0(sprintf("%.1f", tab$signed_pct), "%"),
    abs = paste0(sprintf("%.1f", tab$abs_pct), "%"),
    observed_only_abs = paste0(sprintf("%.1f", tab$baseline_abs_pct), "%"),
    coverage90 = sprintf("%.2f", tab$coverage90)
  ),
  row.names = FALSE
)
cat("\n")

# ---- CHECK 5: beats the observed-only baseline at every horizon ------------
beats <- tab$abs_pct < tab$baseline_abs_pct
check(
  "CHECK 5 beats-observed-only-baseline-at-every-horizon",
  length(beats) == 5L && all(beats),
  paste0(
    "horizons beaten=",
    paste(tab$h[beats], collapse = ","),
    " not beaten=",
    paste(tab$h[!beats], collapse = ",")
  )
)

# ---- CHECK 6/7/8: signed error --------------------------------------------
h_far <- tab$h %in% c(2L, 3L, 4L)
check(
  "CHECK 6 signed-error-within-2pct-at-horizons-2-3-4",
  sum(h_far) == 3L && all(abs(tab$signed_pct[h_far]) <= 2),
  paste0(
    "signed=",
    paste(sprintf("%.2f%%", tab$signed_pct[h_far]), collapse = ", ")
  )
)
h1 <- tab$h == 1L
check(
  "CHECK 7 signed-error-within-12pct-at-horizon-1",
  sum(h1) == 1L && abs(tab$signed_pct[h1]) <= 12,
  paste0("signed=", sprintf("%.2f%%", tab$signed_pct[h1]))
)
h0 <- tab$h == 0L
cat(
  "REPORT [CHECK 8 horizon-0 is reported, not gated] signed=",
  sprintf("%.1f%%", tab$signed_pct[h0]),
  " abs=",
  sprintf("%.1f%%", tab$abs_pct[h0]),
  " observed_only_abs=",
  sprintf("%.1f%%", tab$baseline_abs_pct[h0]),
  " coverage90=",
  sprintf("%.2f", tab$coverage90[h0]),
  "\n",
  sep = ""
)

# ---- CHECK 9: the empirical interval endpoints -----------------------------
# The engine's 5% and 95% draw quantiles MUST equal
# `pred * quantile(truth_pool / pred_pool, c(.05, .95))`, floored at the
# observed count.
#
# Everything on the right-hand side is rebuilt HERE, from the simulated counts
# matrix: the settled pool, the ECDF, the point estimate and the ratio. Nothing
# is read back from the engine, so the check cannot agree with itself.
#
# NOTE WHAT THIS CHECK DOES NOT PIN. p(d) cancels out of the endpoint:
# pred * (truth_s / pred_s) is (obs / p) * truth_s * p / obs_s, which is
# obs * truth_s / obs_s. So the endpoints are a pure ratio estimator and they do
# not depend on the ECDF. CHECK 3 pins the ECDF, CHECK 9 pins the endpoints, and
# neither substitutes for the other. A consequence: a change to p(d) moves the
# endpoints only in the last bits, through floating-point reassociation, so a
# non-zero deviation here after an ECDF change is an artefact and not evidence.
#
# N_SIM = 2001 makes the identity exact rather than close. stats::quantile type
# 7 reads probability p at position (n - 1) * p + 1, which is 101 for p = 0.05
# and 1901 for p = 0.95 when n is 2001. Both are whole numbers, so no
# interpolation happens and the draw at that position is the pool quantile
# itself.
endpoint_err <- numeric(0)
endpoint_n <- 0L
for (i in seq_along(AS_OF)) {
  this_as_of <- AS_OF[i]
  age_all <- as.integer(this_as_of - MONDAYS)
  settled_all <- age_all >= (MAXD - 1L)
  train <- which(settled_all & age_all < (WINDOW * 7L + MAXD))
  p <- cumsum(colSums(COUNTS[train, , drop = FALSE]))
  p <- p / p[MAXD]
  for (d in c(2L, 9L, 16L, 23L, 30L)) {
    cols <- seq_len(d + 1L)
    pool_pred <- rowSums(COUNTS[train, cols, drop = FALSE]) / p[d + 1L]
    rat <- rowSums(COUNTS[train, , drop = FALSE]) / pool_pred
    q <- stats::quantile(rat, c(0.05, 0.95), names = FALSE)
    k <- which(age_all == d & !settled_all)
    obs <- rowSums(COUNTS[k, cols, drop = FALSE])
    pred <- obs / p[d + 1L]
    # which(), not w5[...]: inside a data.table `i` expression a bare `as_of`
    # resolves to the COLUMN of that name, so the as-of filter would silently
    # compare the column with itself and match every row.
    got <- which(w5$as_of == this_as_of & w5$d_observed == d)
    if (length(got) != 1L) {
      next
    }
    endpoint_err <- c(
      endpoint_err,
      abs(w5$q05[got] - pmax(pred * q[1], obs)),
      abs(w5$q95[got] - pmax(pred * q[2], obs))
    )
    endpoint_n <- endpoint_n + 1L
  }
}
check(
  "CHECK 9 empirical-interval-endpoints",
  endpoint_n == 150L && length(endpoint_err) > 0L && max(endpoint_err) == 0,
  paste0(
    "(week, as-of) pairs checked=",
    endpoint_n,
    " endpoints=",
    length(endpoint_err),
    " max absolute deviation=",
    format(max(c(endpoint_err, 0)), digits = 3)
  )
)

# ---- CHECK 10: the table is printed ---------------------------------------
check(
  "CHECK 10 per-horizon-table-printed",
  nrow(tab) == 5L && !anyNA(tab$abs_pct),
  "printed above, five horizons"
)

if (length(failures) > 0) {
  stop(
    "phase3 discriminator FAILED: ",
    paste(failures, collapse = ", "),
    call. = FALSE
  )
}
cat("phase3 discriminator: every check passed\n")
