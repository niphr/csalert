# csfmt_reporting_triangle_v4 and .v4_reporting_triangle_matrix are copies of
# their v3 versions, so they MUST give the same result.

v4_tri_raw <- function() {
  set.seed(3)
  cal <- cstime::dates_by_isoyearweek
  i <- match("2022-50", cal$isoyearweek)
  # week 2 has no report, so the matrix fills a row of zeros for it
  w <- rep(c(0:1, 3:19), each = 3)
  raw <- data.table::rbindlist(lapply(c("nation", "county03"), function(loc) {
    return(data.table::data.table(
      isoyearweek_reference = cal$isoyearweek[i + w],
      reporting_date = as.Date(cal$mon[i + w]) + rep(c(0, 9, 30), 19),
      numerator = c(NA, stats::rpois(56, c(30, 15, 5))),
      location_code = loc,
      age = "total"
    ))
  }))
  return(raw[raw$reporting_date <= as.Date(cal$mon[i + 19]) + 4])
}

test_that("csfmt_reporting_triangle_v4 matches csfmt_reporting_triangle_v3", {
  raw <- v4_tri_raw()
  id <- c("location_code", "age")
  t3 <- csfmt_reporting_triangle_v3(raw, id_cols = id)
  t4 <- csfmt_reporting_triangle_v4(raw, id_cols = id)
  expect_s3_class(t4, "csfmt_reporting_triangle_v4")
  expect_false(inherits(t4, "csfmt_reporting_triangle_v3"))
  for (a in c(
    "as_of",
    "id_cols",
    "reference_col",
    "reporting_col",
    "value_col"
  )) {
    expect_identical(attr(t4, a), attr(t3, a))
  }
  expect_identical(
    data.table::as.data.table(unclass(t4)),
    data.table::as.data.table(unclass(t3))
  )
})

test_that(".v4_reporting_triangle_matrix matches reporting_triangle_matrix", {
  raw <- v4_tri_raw()
  id <- c("location_code", "age")
  t3 <- csfmt_reporting_triangle_v3(raw, id_cols = id)
  t4 <- csfmt_reporting_triangle_v4(raw, id_cols = id)
  for (h in c(7L, 21L, 35L)) {
    expect_identical(
      .v4_reporting_triangle_matrix(t4, h),
      reporting_triangle_matrix(t3, h)
    )
  }
  m <- .v4_reporting_triangle_matrix(t4, 21L)
  # the late reports at delay day 30 go to `late`
  expect_gt(sum(m[[1]]$late), 0)
  expect_identical(m[[1]]$reference[3], "2022-52")
  expect_identical(sum(m[[1]]$mat[3, ]), 0)
})

test_that("csfmt_reporting_triangle_v4 rejects the inputs that v3 rejects", {
  raw <- v4_tri_raw()
  id <- c("location_code", "age")
  bad <- data.table::copy(raw)[,
    reporting_date := data.table::as.IDate(reporting_date)
  ]
  expect_error(csfmt_reporting_triangle_v4(bad, id_cols = id), "must be a Date")
  bad <- data.table::copy(raw)
  bad$reporting_date[2] <- NA
  expect_error(csfmt_reporting_triangle_v4(bad, id_cols = id), "1 missing")
  bad <- data.table::copy(raw)
  bad$reporting_date[2] <- as.Date("2000-01-01")
  expect_error(
    csfmt_reporting_triangle_v4(bad, id_cols = id),
    "before reference"
  )
  bad <- data.table::copy(raw)
  bad$numerator[2] <- -1L
  expect_error(
    csfmt_reporting_triangle_v4(bad, id_cols = id),
    "negative counts"
  )
})
