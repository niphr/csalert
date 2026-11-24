# proportion_stability_v1: proportion errors by delay day, against values
# computed by hand.
#
# Every test here uses max_delay_days = 3, so delay days 0, 1 and 2. A week is
# settled at age >= 2 days. The settled value is the cumulative count at delay
# day 2.

# one long triangle from rows of (Monday of the reference week, delay day,
# numerator, denominator)
.ps_tri <- function(rows, series = "a") {
  d <- data.table::rbindlist(lapply(rows, function(r) {
    data.table::data.table(
      isoyearweek_reference = format(as.Date(r[[1]]), "%G-%V"),
      reporting_date = as.Date(r[[1]]) + as.integer(r[[2]]),
      numerator = as.numeric(r[[3]]),
      denominator = as.numeric(r[[4]])
    )
  }))
  d[, `:=`(indicator = series, location = "nation")]
  return(d)
}

.ps_make <- function(d) {
  return(csfmt_reporting_triangle_v3(d, id_cols = c("indicator", "location")))
}

# Four settled weeks and one week that is not settled. Increments by delay day:
#   W1 2024-01-01  num 2 1 1  den 10 5 5   cum num 2 3 4  cum den 10 15 20
#   W2 2024-01-08  num 1 1 0  den  4 4 2   cum num 1 2 2  cum den  4  8 10
#   W3 2024-01-15  num 3 0 0  den  5 5 5   cum num 3 3 3  cum den  5 10 15
#   W4 2024-01-22  num 0 2 2  den  0 10 10 cum num 0 2 4  cum den  0 10 20
#   W5 2024-01-29  num 5      den  5       (age 0 on as_of 2024-01-29: not settled)
# The settled proportion p is 0.2 in every week.
.ps_rows_hand <- list(
  list("2024-01-01", 0, 2, 10),
  list("2024-01-01", 1, 1, 5),
  list("2024-01-01", 2, 1, 5),
  list("2024-01-08", 0, 1, 4),
  list("2024-01-08", 1, 1, 4),
  list("2024-01-08", 2, 0, 2),
  list("2024-01-15", 0, 3, 5),
  list("2024-01-15", 1, 0, 5),
  list("2024-01-15", 2, 0, 5),
  list("2024-01-22", 1, 2, 10),
  list("2024-01-22", 2, 2, 10),
  list("2024-01-29", 0, 5, 5)
)

test_that("proportion_stability_v1 gives the hand-computed value of every column", {
  tri <- .ps_make(.ps_tri(.ps_rows_hand))
  ps <- proportion_stability_v1(tri, max_delay_days = 3, "denominator")
  expect_identical(
    names(ps),
    c(
      "indicator",
      "location",
      "n_settled",
      "n_eval",
      "delay",
      "day_after",
      "week_after",
      "pct_count",
      "prop_relerr_p50",
      "prop_relerr_p90",
      "prop_abserr_p50",
      "prop_abserr_p90"
    )
  )
  expect_identical(ps$indicator, rep("a", 3))
  expect_identical(ps$location, rep("nation", 3))
  # W1 to W4 are settled with numerator and denominator above 0; W5 is not settled
  expect_identical(ps$n_settled, rep(4L, 3))
  # W4 has a cumulative denominator of 0 at delay 0
  expect_identical(ps$n_eval, c(3L, 4L, 4L))
  expect_identical(ps$delay, 0:2)
  # pooled cum num: d0 2+1+3+0 = 6, d1 3+2+3+2 = 10, d2 4+2+3+4 = 13
  # 600/13 = 46.15 -> 46.2; 1000/13 = 76.92 -> 76.9; 100
  expect_equal(ps$pct_count, c(46.2, 76.9, 100))
  # delay 0, W1 to W3: p_d = 0.2, 0.25, 0.6, p = 0.2
  #   relerr 0, 25, 200: p50 25; p90 at h = 2 * 0.9 = 1.8, 25 + 0.8 * 175 = 165
  #   abserr 0, 5, 40:   p50 5;  p90 5 + 0.8 * 35 = 33
  # delay 1, W1 to W4: p_d = 0.2, 0.25, 0.3, 0.2
  #   relerr sorted 0, 0, 25, 50: p50 at h = 1.5, 12.5; p90 at h = 2.7, 25 + 0.7 * 25 = 42.5
  #   abserr sorted 0, 0, 5, 10:  p50 2.5; p90 5 + 0.7 * 5 = 8.5
  # delay 2: p_d = p in every week, so every error is 0
  expect_equal(ps$prop_relerr_p50, c(25, 12.5, 0))
  expect_equal(ps$prop_relerr_p90, c(165, 42.5, 0))
  expect_equal(ps$prop_abserr_p50, c(5, 2.5, 0))
  expect_equal(ps$prop_abserr_p90, c(33, 8.5, 0))
})

test_that("proportion_stability_v1 gives day_after and week_after by delay day", {
  # three weeks settled at max_delay_days = 57, and a week 8 weeks later that
  # moves the as-of date to 2024-03-11
  rows <- list(
    list("2024-01-01", 0, 1, 5),
    list("2024-01-08", 0, 1, 5),
    list("2024-01-15", 0, 1, 5),
    list("2024-03-11", 0, 1, 5)
  )
  ps <- proportion_stability_v1(.ps_make(.ps_tri(rows)), 57, "denominator")
  expect_identical(ps$delay, 0:56)
  at <- match(c(0L, 6L, 7L, 13L, 14L, 56L), ps$delay)
  expect_identical(ps$day_after[at], c(-6L, 0L, 1L, 7L, 8L, 50L))
  expect_identical(ps$week_after[at], c(0L, NA, 1L, NA, 2L, 8L))
})

test_that("proportion_stability_v1 errors are 0 when both counts share a delay pattern", {
  inc <- list(c(4, 2, 1), c(1, 1, 3), c(6, 0, 2), c(2, 5, 1), c(3, 3, 3))
  mondays <- as.character(as.Date("2024-01-01") + 7 * 0:4)
  rows <- list()
  for (w in seq_along(inc)) {
    for (k in 0:2) {
      # the denominator is 7 times the numerator in every cell
      rows[[length(rows) + 1L]] <- list(
        mondays[w],
        k,
        inc[[w]][k + 1L],
        7 * inc[[w]][k + 1L]
      )
    }
  }
  ps <- proportion_stability_v1(.ps_make(.ps_tri(rows)), 3, "denominator")
  expect_identical(nrow(ps), 3L)
  expect_identical(ps$n_eval, rep(5L, 3))
  for (col in c(
    "prop_relerr_p50",
    "prop_relerr_p90",
    "prop_abserr_p50",
    "prop_abserr_p90"
  )) {
    expect_identical(ps[[col]], rep(0, 3), info = col)
  }
})

test_that("proportion_stability_v1 ignores a report at delay max_delay_days or later", {
  base <- proportion_stability_v1(
    .ps_make(.ps_tri(.ps_rows_hand)),
    3,
    "denominator"
  )
  # W1 and W2 get late reports at delay 3 and 10, before the as-of date
  rows_late <- c(
    .ps_rows_hand,
    list(list("2024-01-01", 3, 7, 1), list("2024-01-08", 10, 4, 50))
  )
  late <- proportion_stability_v1(
    .ps_make(.ps_tri(rows_late)),
    3,
    "denominator"
  )
  expect_identical(late, base)
})

test_that("proportion_stability_v1 a denominator of 0 at an early delay lowers n_eval there only", {
  mondays <- as.character(as.Date("2024-01-01") + 7 * 0:3)
  rows <- list()
  for (w in seq_along(mondays)) {
    rows <- c(
      rows,
      list(
        list(mondays[w], 0, 1, 5),
        list(mondays[w], 1, 1, 5),
        list(mondays[w], 2, 1, 5)
      )
    )
  }
  base <- proportion_stability_v1(.ps_make(.ps_tri(rows)), 3, "denominator")
  expect_identical(base$n_eval, rep(4L, 3))
  # move the delay-0 denominator of week 2 to delay 1: same settled total
  rows[[4]] <- list(mondays[2], 0, 1, 0)
  rows[[5]] <- list(mondays[2], 1, 1, 10)
  ps <- proportion_stability_v1(.ps_make(.ps_tri(rows)), 3, "denominator")
  expect_identical(ps$n_eval, c(3L, 4L, 4L))
  expect_identical(ps$n_settled, rep(4L, 3))
})

test_that("proportion_stability_v1 stops when the two matrices differ", {
  tri <- .ps_make(.ps_tri(.ps_rows_hand))
  real <- reporting_triangle_matrix
  # One long triangle gives the same reference weeks to both columns, so the
  # mock makes the denominator series span one reference week fewer.
  local_mocked_bindings(
    reporting_triangle_matrix = function(triangle, max_delay_days, value_col) {
      x <- real(triangle, max_delay_days, value_col)
      if (value_col == "denominator") {
        x <- lapply(x, function(s) {
          s$reference <- s$reference[-1]
          s$mat <- s$mat[-1, , drop = FALSE]
          s$late <- s$late[-1]
          return(s)
        })
      }
      return(x)
    }
  )
  num <- reporting_triangle_matrix(tri, 3, "numerator")[[1]]
  den <- reporting_triangle_matrix(tri, 3, "denominator")[[1]]
  expect_false(identical(num$reference, den$reference))
  expect_false(identical(dim(num$mat), dim(den$mat)))
  expect_error(
    proportion_stability_v1(tri, 3, "denominator"),
    "differ in `reference` or `dim`"
  )
})

test_that("proportion_stability_v1 gives no rows to a series with fewer than 3 weeks", {
  a <- .ps_tri(.ps_rows_hand, series = "a")
  # series b: 3 settled weeks, but W3 has a settled denominator of 0
  b <- .ps_tri(
    list(
      list("2024-01-01", 0, 1, 5),
      list("2024-01-08", 0, 1, 5),
      list("2024-01-15", 0, 1, 0),
      list("2024-01-29", 0, 1, 5)
    ),
    series = "b"
  )
  tri <- .ps_make(rbind(a, b))
  expect_no_warning(ps <- proportion_stability_v1(tri, 3, "denominator"))
  expect_identical(unique(ps$indicator), "a")
  expect_identical(nrow(ps), 3L)
  # series b alone gives an empty table
  expect_no_warning(
    ps_b <- proportion_stability_v1(.ps_make(b), 3, "denominator")
  )
  expect_identical(nrow(ps_b), 0L)
})
