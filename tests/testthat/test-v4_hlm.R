# signal_detection_hlm_v4 is a copy of signal_detection_hlm.csfmt_ensemble_v3.
# On the same draws, its values MUST be identical() to those of v3. Only the
# names differ.

# The ISO weeks of a series: `n` weeks that end in `last`.
v4h_weeks <- function(n = 370L, last = "2023-03") {
  cal <- cstime::dates_by_isoyearweek
  i <- match(last, cal$isoyearweek)
  return(cal$isoyearweek[seq(i - n + 1L, i)])
}

# The weekly mean of the test series: a winter peak in each season.
v4h_lambda <- function(weeks, peak) {
  sw <- cstime::isoyearweek_to_seasonweek_n(weeks)
  return(20 + peak * exp(-(sw - 25)^2 / 40))
}

# Raw reports of two series over about 7 seasons. With `delays = TRUE`, each
# week is reported over delay days 0 to 34, and the as-of date is 2 days
# after the Monday of the last week. Without, each week is reported once, 3
# days after its Monday, and every week is complete.
v4h_raw <- function(delays, seed = 7L) {
  set.seed(seed)
  cal <- cstime::dates_by_isoyearweek
  weeks <- v4h_weeks()
  monday <- as.Date(cal$mon[match(weeks, cal$isoyearweek)])
  shares <- stats::dgamma(seq(0, 34) + 0.5, shape = 2, rate = 0.3)
  rows <- list()
  for (loc in c("nation", "county03")) {
    n <- stats::rpois(
      length(weeks),
      v4h_lambda(weeks, c(nation = 300, county03 = 90)[[loc]])
    )
    for (k in seq_along(weeks)) {
      if (delays) {
        cnt <- as.integer(stats::rmultinom(1, n[k], shares))
        day <- seq(0, 34)
      } else {
        cnt <- n[k]
        day <- 3
      }
      keep <- cnt > 0L
      rows[[length(rows) + 1L]] <- data.table::data.table(
        isoyearweek_reference = weeks[k],
        reporting_date = monday[k] + day[keep],
        numerator = cnt[keep],
        location_code = loc,
        age = "total"
      )
    }
  }
  raw <- data.table::rbindlist(rows)
  return(raw[raw$reporting_date <= monday[length(monday)] + 2L])
}

# The v3 and the v4 ensemble of the same draws. "ecdf" gives 100 draws from
# the ECDF nowcast, and "pass" one draw from the passthrough. Both get NA
# weeks: three whole weeks of "nation" in its second season, and, with many
# draws, one NA draw in a later week.
v4h_pair <- function(kind) {
  id <- c("location_code", "age")
  raw <- v4h_raw(delays = kind == "ecdf")
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = id)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = id)
  if (kind == "ecdf") {
    set.seed(4)
    e3 <- nowcast_delay_ecdf_v1(tri3, max_delay_days = 35, n_sim = 100)
    e4 <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 100)
  } else {
    e3 <- nowcast_passthrough_to_ensemble_v1(tri3, max_delay_days = 7)
    e4 <- nowcast_passthrough_v4(tri4, max_delay_days = 7)
  }
  na_rows <- which(e4$data$location_code == "nation")[100:102]
  e3$draws$numerator_nowcasted[na_rows, ] <- NA_real_
  e4$draws$numerator[na_rows, ] <- NA_real_
  if (kind == "ecdf") {
    e3$draws$numerator_nowcasted[300, 1] <- NA_real_
    e4$draws$numerator[300, 1] <- NA_real_
  }
  return(list(e3 = e3, e4 = e4, na_rows = na_rows))
}

V4H_Q <- c(
  "q02x5",
  "q05x0",
  "q10x0",
  "q25x0",
  "q50x0",
  "q75x0",
  "q90x0",
  "q95x0",
  "q97x5"
)

# Each v3 output and its v4 name. "draws" is a draw matrix. "data" is a
# column of $data in v4, and of the ens_collapse() output in v3.
v4h_map <- function(m3, m4) {
  return(data.frame(
    where = c("draws", rep("data", 12)),
    v3 = c(
      paste0(m3, "_hlmstatus"),
      "hlm_threshold",
      paste0(m3, "_hlmstatus_prob_", c("null", "high")),
      paste0(m3, "_hlmstatus_", V4H_Q)
    ),
    v4 = c(
      paste0(m4, "_hlm"),
      paste0(m4, "_hlm_thr"),
      paste0(m4, "_hlm_prob_", c("null", "high")),
      paste0(m4, "_hlm_", V4H_Q)
    )
  ))
}

# Run v3 and v4 on the pair, and expect every v3 output to have a v4 name in
# the map with identical values, and no output outside the map.
v4h_expect_equivalent <- function(pair, ...) {
  e3 <- pair$e3
  e4 <- pair$e4
  expect_identical(e4$data, e3$data)
  expect_identical(e4$draws$numerator, e3$draws$numerator_nowcasted)
  in3_data <- names(ens_collapse(e3))
  in3_draws <- names(e3$draws)
  e4_before <- data.table::copy(e4$data)

  h3 <- signal_detection_hlm(e3, measure = "numerator_nowcasted", ...)
  h4 <- signal_detection_hlm_v4(e4, measure = "numerator", ...)
  c3 <- ens_collapse(h3)
  map <- v4h_map("numerator_nowcasted", "numerator")

  # No v3 output is left unmapped, and v4 adds nothing outside the map.
  expect_setequal(
    c(setdiff(names(c3), in3_data), setdiff(names(h3$draws), in3_draws)),
    map$v3
  )
  expect_identical(
    setdiff(names(h4$data), names(e4$data)),
    map$v4[map$where == "data"]
  )
  expect_identical(
    setdiff(names(h4$draws), names(e4$draws)),
    map$v4[map$where == "draws"]
  )

  for (i in seq_len(nrow(map))) {
    if (map$where[i] == "draws") {
      expect_identical(
        h4$draws[[map$v4[i]]],
        h3$draws[[map$v3[i]]],
        label = map$v4[i]
      )
    } else {
      expect_identical(h4$data[[map$v4[i]]], c3[[map$v3[i]]], label = map$v4[i])
    }
  }
  # The columns that were there keep their values, and the input does not
  # change.
  expect_identical(h4$data[, names(e4$data), with = FALSE], e4_before)
  expect_identical(e4$data, e4_before)
  return(h4)
}

test_that("with 100 ECDF draws, signal_detection_hlm_v4 is identical to v3", {
  pair <- v4h_pair("ecdf")
  h4 <- v4h_expect_equivalent(pair)
  thr <- h4$data$numerator_hlm_thr
  # The test is not trivial: some weeks have a limit and some do not, the NA
  # weeks have no draws, and some weeks have draws on both sides of the limit.
  expect_gt(sum(!is.na(thr)), 100L)
  expect_gt(sum(is.na(thr)), 100L)
  expect_true(all(is.na(h4$draws$numerator_hlm[pair$na_rows, ])))
  p <- h4$data$numerator_hlm_prob_high
  expect_gt(sum(p > 0 & p < 1, na.rm = TRUE), 0L)
  expect_gt(sum(h4$draws$numerator_hlm == 2L, na.rm = TRUE), 0L)
})

test_that("with one passthrough draw, signal_detection_hlm_v4 is identical to v3", {
  pair <- v4h_pair("pass")
  h4 <- v4h_expect_equivalent(pair)
  expect_identical(ncol(h4$draws$numerator_hlm), 1L)
  expect_gt(sum(!is.na(h4$data$numerator_hlm_thr)), 100L)
  expect_gt(sum(h4$draws$numerator_hlm == 2L, na.rm = TRUE), 0L)
  expect_true(all(is.na(h4$draws$numerator_hlm[pair$na_rows, ])))
})

test_that("signal_detection_hlm_v4 is identical to v3 with baseline_isoyears = 3", {
  h4 <- v4h_expect_equivalent(v4h_pair("pass"), baseline_isoyears = 3)
  expect_gt(sum(!is.na(h4$data$numerator_hlm_thr)), 200L)
})

# A small ensemble of one series over 6 years, with 20 draws.
v4h_small <- function(measure = "cases") {
  weeks <- v4h_weeks(n = 320L)
  set.seed(5)
  draws <- list(matrix(
    stats::rpois(320 * 20, v4h_lambda(weeks, 100)),
    nrow = 320
  ))
  names(draws) <- measure
  return(csfmt_ensemble_v4(
    data.table::data.table(location_code = "nation", isoyearweek = weeks),
    id_cols = "location_code",
    draws = draws
  ))
}

test_that("a rerun on the same measure replaces the columns and the draws", {
  ens <- v4h_small()
  first <- signal_detection_hlm_v4(ens, "cases", baseline_isoyears = 5)
  rerun <- signal_detection_hlm_v4(first, "cases", baseline_isoyears = 3)
  fresh <- signal_detection_hlm_v4(ens, "cases", baseline_isoyears = 3)
  # 3 and 5 years give other limits, so a column left from the first run is
  # visible.
  expect_false(identical(first$data$cases_hlm_thr, fresh$data$cases_hlm_thr))
  expect_identical(anyDuplicated(names(rerun$data)), 0L)
  expect_identical(anyDuplicated(names(rerun$draws)), 0L)
  expect_identical(names(rerun$data), names(fresh$data))
  expect_identical(names(rerun$draws), names(fresh$draws))
  for (col in setdiff(names(fresh$data), names(ens$data))) {
    expect_identical(rerun$data[[col]], fresh$data[[col]], label = col)
  }
  expect_identical(rerun$draws, fresh$draws)
})

test_that("the 63-byte check of the new names runs before the limit", {
  # The limit stops, so only the name check can give the 63-byte error.
  testthat::local_mocked_bindings(
    .v4_hlm_threshold = function(...) stop("the limit ran", call. = FALSE),
    .package = "csalert"
  )
  # 50 bytes + "_hlm_prob_null" is 64 bytes.
  m <- strrep("n", 50)
  expect_error(signal_detection_hlm_v4(v4h_small(m), m), "longer than 63 bytes")
  m <- strrep("n", 49)
  expect_error(signal_detection_hlm_v4(v4h_small(m), m), "the limit ran")
})

test_that("a measure that ends in a reserved suffix is an error", {
  for (m in c("cases_hlm", "cases_mem", "cases_trend_pinc")) {
    expect_error(
      signal_detection_hlm_v4(v4h_small(m), m),
      "reserved suffix",
      label = m
    )
  }
  expect_error(
    signal_detection_hlm_v4(v4h_small(), "other"),
    "must name one matrix in \\$draws"
  )
})

test_that("signal_detection_hlm_v4 does not change .Random.seed", {
  ens <- v4h_small()
  set.seed(21)
  before <- get(".Random.seed", envir = globalenv())
  signal_detection_hlm_v4(ens, "cases")
  # identical() inside expect_true(): testthat cannot print a diff of two
  # .Random.seed vectors.
  expect_true(identical(get(".Random.seed", envir = globalenv()), before))

  env <- globalenv()
  saved <- get(".Random.seed", envir = env)
  rm(".Random.seed", envir = env)
  signal_detection_hlm_v4(ens, "cases")
  absent <- !exists(".Random.seed", envir = env, inherits = FALSE)
  assign(".Random.seed", saved, envir = env)
  expect_true(absent)
})

test_that("signal_detection_hlm_v4 is exported", {
  ns_file <- file.path(system.file(package = "csalert"), "NAMESPACE")
  expect_true(file.exists(ns_file))
  expect_true("export(signal_detection_hlm_v4)" %in% trimws(readLines(ns_file)))
})

test_that("an unknown named argument is an error", {
  # The function takes no `...`, so a misspelt argument cannot become a
  # silent default. The name is not the start of any argument name: R
  # matches a start such as `baseline_isoyear` to the argument by partial matching.
  expect_error(
    signal_detection_hlm_v4(v4h_small(), "cases", baseline_years = 4),
    "unused argument"
  )
})
