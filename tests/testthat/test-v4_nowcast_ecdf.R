# nowcast_ecdf_v4 is a copy of nowcast_delay_ecdf_v1. With the same triangle
# and seed, its draws MUST be identical() to those of v3.

# Two series of 60 reference weeks, reported over delay days 0 to 34. The delay
# distribution gets slower each week, so the settled weeks in the window
# differ from those outside it, and a change of delay_window changes the
# draws. The denominator is 10 times the numerator plus noise.
v4_ecdf_raw <- function(n_weeks = 60L, max_delay_days = 35L, seed = 11L) {
  set.seed(seed)
  cal <- cstime::dates_by_isoyearweek
  i0 <- match("2022-01", cal$isoyearweek)
  idx <- i0 + seq_len(n_weeks) - 1L
  rows <- list()
  for (loc in c("nation", "county03")) {
    for (k in seq_len(n_weeks)) {
      shares <- stats::dgamma(
        seq(0, max_delay_days - 1L) + 0.5,
        shape = 2 + k / 20,
        rate = 0.3
      )
      cnt <- as.integer(stats::rmultinom(1, stats::rpois(1, 400), shares))
      keep <- cnt > 0L
      rows[[length(rows) + 1L]] <- data.table::data.table(
        isoyearweek_reference = cal$isoyearweek[idx[k]],
        reporting_date = as.Date(cal$mon[idx[k]]) +
          (seq_len(max_delay_days) - 1L)[keep],
        numerator = cnt[keep],
        denominator = 10L * cnt[keep] + stats::rpois(sum(keep), 5),
        location_code = loc,
        age = "total"
      )
    }
  }
  raw <- data.table::rbindlist(rows)
  as_of <- as.Date(cal$mon[idx[n_weeks]]) + 2L
  return(raw[raw$reporting_date <= as_of])
}

V4_ECDF_ID <- c("location_code", "age")

test_that("nowcast_ecdf_v4 gives draws identical to nowcast_delay_ecdf_v1", {
  raw <- v4_ecdf_raw()
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = V4_ECDF_ID)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = V4_ECDF_ID)
  set.seed(4)
  e3 <- nowcast_delay_ecdf_v1(
    tri3,
    max_delay_days = 35,
    n_sim = 300,
    denominator_col = "denominator"
  )
  e4 <- nowcast_ecdf_v4(
    tri4,
    max_delay_days = 35,
    seed = 4,
    n_sim = 300,
    denominator_col = "denominator"
  )
  expect_identical(e4$draws$numerator, e3$draws$numerator_nowcasted)
  expect_identical(e4$draws$denominator, e3$draws$denominator_nowcasted)
  expect_identical(names(e4$draws), c("numerator", "denominator"))
  expect_identical(e4$data, e3$data)
  # the draws are not degenerate, so the identity is not trivial
  spread <- apply(e4$draws$numerator, 1, function(r) diff(range(r)))
  expect_gt(sum(spread > 0), 4L)
})

test_that("nowcast_ecdf_v4 is identical to v3 with delay_window = NULL", {
  raw <- v4_ecdf_raw(n_weeks = 40L, seed = 3L)
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = V4_ECDF_ID)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = V4_ECDF_ID)
  set.seed(9)
  e3 <- nowcast_delay_ecdf_v1(
    tri3,
    max_delay_days = 21,
    n_sim = 50,
    delay_window = NULL
  )
  e4 <- nowcast_ecdf_v4(
    tri4,
    max_delay_days = 21,
    seed = 9,
    n_sim = 50,
    delay_window = NULL
  )
  expect_identical(e4$draws$numerator, e3$draws$numerator_nowcasted)
})

test_that("nowcast_ecdf_v4 returns a full csfmt_ensemble_v4", {
  tri4 <- csfmt_reporting_triangle_v4(v4_ecdf_raw(), id_cols = V4_ECDF_ID)
  e4 <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 20)
  expect_s3_class(e4, "csfmt_ensemble_v4")
  expect_identical(e4$state, "full")
  expect_identical(e4$id_cols, V4_ECDF_ID)
  expect_identical(e4$time_col, "isoyearweek")
  expect_identical(dim(e4$draws$numerator), c(nrow(e4$data), 20L))
})

test_that("nowcast_ecdf_v4 does not change the random-number state", {
  tri4 <- csfmt_reporting_triangle_v4(v4_ecdf_raw(), id_cols = V4_ECDF_ID)
  set.seed(123)
  before <- get(".Random.seed", envir = globalenv())
  a <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 20)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  b <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 20)
  expect_identical(a$draws, b$draws)
  c5 <- nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 5, n_sim = 20)
  expect_false(identical(a$draws, c5$draws))
})

test_that("nowcast_ecdf_v4 rejects a measure name with a reserved suffix", {
  raw <- v4_ecdf_raw(n_weeks = 40L)
  data.table::setnames(raw, "numerator", "cases_mem")
  tri4 <- csfmt_reporting_triangle_v4(
    raw,
    id_cols = V4_ECDF_ID,
    value_col = "cases_mem"
  )
  expect_error(
    nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 4, n_sim = 5),
    "reserved suffix"
  )
})

test_that("nowcast_ecdf_v4 needs a v4 triangle and a whole-number seed", {
  raw <- v4_ecdf_raw(n_weeks = 40L)
  tri3 <- csfmt_reporting_triangle_v3(raw, id_cols = V4_ECDF_ID)
  tri4 <- csfmt_reporting_triangle_v4(raw, id_cols = V4_ECDF_ID)
  expect_error(nowcast_ecdf_v4(tri3, max_delay_days = 35, seed = 4))
  expect_error(nowcast_ecdf_v4(tri4, max_delay_days = 35))
  expect_error(
    nowcast_ecdf_v4(tri4, max_delay_days = 35, seed = 1.5),
    "one whole number"
  )
})
