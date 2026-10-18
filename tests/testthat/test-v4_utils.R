# The shared v4 helpers are copies of v3 or v1 helpers, so they MUST give the
# same result.

test_that(".v4_isoyearweek_week_start matches isoyearweek_week_start", {
  x <- c("2026-01", "2020-53", "2023-30", "2026-99", NA)
  expect_identical(.v4_isoyearweek_week_start(x), isoyearweek_week_start(x))
  expect_equal(.v4_isoyearweek_week_start("2026-01"), as.Date("2025-12-29"))
})

test_that(".v4_set_time_series_id matches set_time_series_id", {
  d <- data.table::data.table(
    location_code = c("nation", "nation", "county03"),
    age = c("total", "0-4", "total"),
    x = 1:3
  )
  a <- data.table::copy(d)
  b <- data.table::copy(d)
  .v4_set_time_series_id(a, c("location_code", "age"))
  set_time_series_id(b, c("location_code", "age"))
  expect_identical(a, b)
})

test_that(".v4_row_mean and .v4_row_sd match row_mean and row_sd", {
  set.seed(1)
  m <- matrix(stats::rnorm(40), 8)
  m[2, 3] <- NA
  for (na in c(FALSE, TRUE)) {
    expect_identical(
      .v4_row_mean(m, na.rm = na),
      csalert:::row_mean(m, na.rm = na)
    )
    expect_identical(.v4_row_sd(m, na.rm = na), csalert:::row_sd(m, na.rm = na))
  }
})

test_that("the MEM helpers match the v3 MEM helpers", {
  w <- cstime::dates_by_isoyearweek$isoyearweek
  iyw <- w[match("2015-30", w) + 0:(52 * 7 - 1)]
  set.seed(2)
  lam <- 20 + 60 * exp(-(cstime::isoyearweek_to_seasonweek_n(iyw) - 25)^2 / 40)
  d <- data.table::data.table(
    time_series_id = "a",
    season = cstime::isoyearweek_to_season_c(iyw),
    seasonweek = cstime::isoyearweek_to_seasonweek_n(iyw),
    point = as.numeric(stats::rpois(length(iyw), lam))
  )
  # v4 adds 3 fit fields to each fit. Every other value is identical to v3.
  v4_only <- c("mem_postepidemic", "mem_season_start", "mem_season_weeks")
  drop_v4_only <- function(r) {
    r$thr_all <- lapply(r$thr_all, function(t) {
      return(t[, setdiff(names(t), v4_only), with = FALSE])
    })
    return(r)
  }
  args <- list(d, 2, 5, 10, 30, "2018/2019")
  v4 <- do.call(.v4_mem_estimate_thresholds, args)
  v3 <- do.call(csalert:::mem_estimate_thresholds, args)
  expect_identical(drop_v4_only(v4), v3)
  expect_gt(length(v4$thr_all), 2L)
  expect_gt(length(v4$provisional), 0L)
  expect_identical(
    drop_v4_only(.v4_mem_estimate_thresholds(d, 2, 5, 10, 30, NULL)),
    csalert:::mem_estimate_thresholds(d, 2, 5, 10, 30, NULL)
  )
  # fewer than 2 seasons with a count above 0 give no fit
  zero <- data.frame(a = rep(0, 30), b = rep(0, 30), c = 1:30)
  expect_null(.v4_mem_fit(zero))
  expect_null(.v4_mem_fit(NULL))
})

test_that("the MEM extract gives the 3 fit fields of the fit", {
  fit <- list(
    epidemic.thresholds = c(1.5, 1.25),
    epi.intervals = matrix(c(0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 4), nrow = 3),
    mean.start = 13,
    mean.length = 12
  )
  r <- .v4_mem_extract_thresholds(fit)
  expect_identical(r$mem_postepidemic, 1.25)
  expect_identical(r$mem_season_start, 13L)
  expect_identical(r$mem_season_weeks, 12L)
  expect_identical(
    unlist(r[, c("mem_preepidemic", "mem_medium", "mem_high", "mem_veryhigh")]),
    c(mem_preepidemic = 1.5, mem_medium = 2, mem_high = 3, mem_veryhigh = 4)
  )
})

test_that(".v4_collapse_status_into matches the probabilities of collapse_status_into", {
  set.seed(3)
  M <- matrix(sample(c(1:5, NA), 6 * 40, replace = TRUE), nrow = 6)
  # Row 2 has no draw, as a filled-in week has none.
  M[2, ] <- NA_integer_
  levs <- c("preepidemic", "low", "medium", "high", "veryhigh")
  probs <- c(0.05, 0.5, 0.95)
  a <- data.table::data.table(isoyearweek = sprintf("2023-%02d", 1:6))
  b <- data.table::copy(a)
  .v4_collapse_status_into(a, "cases_mem", M, levs)
  csalert:::collapse_status_into(b, "cases_mem", M, levs, probs)
  # v4 writes the probabilities, and not the ordinal percentiles.
  expect_identical(names(a), c("isoyearweek", paste0("cases_mem_prob_", levs)))
  # The one allowed difference: v4 writes NA where v3 writes NaN, the mean of
  # no draws. Map NaN to NA on the v3 side, and every value is identical.
  b3 <- b[, names(a), with = FALSE]
  pcols <- paste0("cases_mem_prob_", levs)
  nan <- vapply(b3[, pcols, with = FALSE], is.nan, logical(nrow(b3)))
  # v3 writes NaN in every level of row 2, and nowhere else.
  expect_identical(which(rowSums(nan) > 0), 2L)
  expect_true(all(nan[2, ]))
  for (col in pcols) {
    b3[is.nan(get(col)), (col) := NA_real_]
  }
  expect_identical(a, b3)
  expect_false(any(vapply(
    a[, pcols, with = FALSE],
    function(v) {
      return(any(is.nan(v)))
    },
    logical(1)
  )))
})
