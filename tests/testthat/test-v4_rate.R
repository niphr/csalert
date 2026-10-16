# ens_add_rate_v4 is a copy of ens_add_rate.csfmt_ensemble_v3. Its rate MUST
# be identical() to that of v3, also for 0 / 0, a zero denominator, NA and a
# numerator above its denominator.

v4r_data <- function() {
  data.table::data.table(
    location_code = rep(c("a", "b"), each = 3),
    isoyearweek = rep(c("2023-01", "2023-02", "2023-03"), 2)
  )
}

# 6 rows and 4 draws. Row 1 holds 0 / 0, 5 / 0, NA / 10 and 10 / NA. Row 2
# holds a numerator above its denominator.
v4r_draws <- function() {
  set.seed(9)
  D <- matrix(stats::rpois(24, 200), 6)
  N <- matrix(stats::rbinom(24, D, 0.1), 6)
  N[1, ] <- c(0, 5, NA, 10)
  D[1, ] <- c(0, 0, 10, NA)
  N[2, 1] <- D[2, 1] + 7
  list(numerator = N * 1, denominator = D * 1)
}

test_that("ens_add_rate_v4 gives a rate identical to v3", {
  dr <- v4r_draws()
  e3 <- csfmt_ensemble_v3(v4r_data(), id_cols = "location_code", draws = dr)
  e4 <- csfmt_ensemble_v4(v4r_data(), id_cols = "location_code", draws = dr)
  expect_warning(
    r3 <- ens_add_rate(e3, "numerator", "denominator", per = 100, name = "r"),
    "rate capped"
  )
  expect_warning(
    r4 <- ens_add_rate_v4(
      e4,
      "numerator",
      "denominator",
      per = 100,
      name = "r"
    ),
    "rate capped"
  )
  expect_identical(r4$draws$r, r3$draws$r)
  expect_identical(r4$draws$numerator, e4$draws$numerator)
  expect_identical(r4$data, e4$data)
  expect_s3_class(r4, "csfmt_ensemble_v4")
})

test_that("0 / 0, a zero denominator and NA give NA, and the cap is per", {
  dr <- v4r_draws()
  e4 <- csfmt_ensemble_v4(v4r_data(), id_cols = "location_code", draws = dr)
  r <- suppressWarnings(
    ens_add_rate_v4(e4, "numerator", "denominator", per = 1000, name = "r")
  )$draws$r
  row1 <- which(e4$data$location_code == "a" & e4$data$isoyearweek == "2023-01")
  expect_identical(r[row1, ], rep(NA_real_, 4))
  expect_identical(max(r, na.rm = TRUE), 1000)
  ok <- !is.na(e4$draws$denominator) &
    e4$draws$denominator > 0 &
    e4$draws$numerator <= e4$draws$denominator
  ok[is.na(ok)] <- FALSE
  expect_identical(
    r[ok],
    1000 * e4$draws$numerator[ok] / e4$draws$denominator[ok]
  )
})

test_that("ens_add_rate_v4 works on a one-draw passthrough ensemble", {
  cal <- cstime::dates_by_isoyearweek
  i <- match("2023-01", cal$isoyearweek)
  raw <- data.table::data.table(
    isoyearweek_reference = cal$isoyearweek[i + 0:5],
    reporting_date = as.Date(cal$mon[i + 0:5]) + 3,
    numerator = c(3, 0, 5, 8, 0, 2),
    denominator = c(100, 0, 90, 80, 70, 60),
    location_code = "a"
  )
  tri <- csfmt_reporting_triangle_v4(raw, id_cols = "location_code")
  ens <- nowcast_passthrough_v4(
    tri,
    max_delay_days = 7,
    denominator_col = "denominator"
  )
  out <- ens_add_rate_v4(ens, "numerator", "denominator", name = "rate")
  expect_identical(
    out$draws$rate[, 1],
    c(3, NA, 100 * 5 / 90, 100 * 8 / 80, 0, 100 * 2 / 60)
  )
})

test_that("a rerun replaces the rate, and the input is not changed", {
  e4 <- csfmt_ensemble_v4(
    v4r_data(),
    id_cols = "location_code",
    draws = v4r_draws()
  )
  one <- suppressWarnings(
    ens_add_rate_v4(e4, "numerator", "denominator", name = "r")
  )
  two <- suppressWarnings(
    ens_add_rate_v4(one, "numerator", "denominator", name = "r")
  )
  expect_identical(names(two$draws), c("numerator", "denominator", "r"))
  expect_identical(two, one)
  expect_identical(names(e4$draws), c("numerator", "denominator"))
})

test_that("ens_add_rate_v4 checks the name and the measures", {
  e4 <- csfmt_ensemble_v4(
    v4r_data(),
    id_cols = "location_code",
    draws = v4r_draws()
  )
  add <- function(name) {
    suppressWarnings(ens_add_rate_v4(
      e4,
      "numerator",
      "denominator",
      name = name
    ))
  }
  expect_error(
    suppressWarnings(ens_add_rate_v4(e4, "numerator", "denominator")),
    "name"
  )
  expect_error(add(strrep("r", 64)), "longer than 63 bytes")
  expect_no_error(add(strrep("r", 63)))
  expect_error(add("r_trend_gr"), "reserved suffix")
  expect_error(add("r_hlm"), "reserved suffix")
  expect_error(
    ens_add_rate_v4(e4, "numerator", "nope", name = "r"),
    "must both be measures"
  )
})

test_that("ens_add_rate_v4 does not change .Random.seed", {
  e4 <- csfmt_ensemble_v4(
    v4r_data(),
    id_cols = "location_code",
    draws = v4r_draws()
  )
  set.seed(31)
  before <- get(".Random.seed", envir = globalenv())
  suppressWarnings(ens_add_rate_v4(e4, "numerator", "denominator", name = "r"))
  # identical() inside expect_true(): testthat cannot print a diff of two
  # .Random.seed vectors.
  expect_true(identical(get(".Random.seed", envir = globalenv()), before))
})

test_that("ens_add_rate_v4 is exported", {
  ns_file <- file.path(system.file(package = "csalert"), "NAMESPACE")
  expect_true(file.exists(ns_file))
  expect_true("export(ens_add_rate_v4)" %in% trimws(readLines(ns_file)))
})

test_that("a name that is a column of $data is an error", {
  e4 <- csfmt_ensemble_v4(
    v4r_data(),
    id_cols = "location_code",
    draws = v4r_draws()
  )
  add <- function(name) {
    suppressWarnings(ens_add_rate_v4(e4, "numerator", "denominator", name = name))
  }
  # An identity column, the time column, and a column the constructor adds.
  expect_error(add("location_code"), "is a column of $data", fixed = TRUE)
  expect_error(add("isoyearweek"), "is a column of $data", fixed = TRUE)
  expect_error(add("time_series_id"), "is a column of $data", fixed = TRUE)
  # A name that is only a draw matrix is replaced.
  expect_identical(names(add("denominator")$draws), c("numerator", "denominator"))
})
