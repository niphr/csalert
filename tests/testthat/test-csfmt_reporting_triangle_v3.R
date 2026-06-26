# csfmt_reporting_triangle_v3: input contract + ref x delay reshape.

ID <- c("indicator", "location", "age", "sex")

mk_triangle <- function() {
  # one series; reference weeks 2020-01..03, reports arriving with delays 0/1/2
  data.table::data.table(
    indicator = "flu", location = "nation", age = "total", sex = "total",
    isoyearweek_reference = c("2020-01", "2020-01", "2020-02", "2020-02", "2020-03"),
    isoyearweek_reporting = c("2020-01", "2020-02", "2020-02", "2020-03", "2020-03"),
    numerator             = c(5,         2,         7,         1,         4)
  )
}

test_that("constructor validates and records the as-of boundary", {
  tri <- csfmt_reporting_triangle_v3(mk_triangle(), id_cols = ID)
  expect_s3_class(tri, "csfmt_reporting_triangle_v3")
  expect_equal(attr(tri, "as_of"), "2020-03")
  expect_true("time_series_id" %in% names(tri))
})

test_that("rejects reporting-before-reference and negative counts", {
  bad1 <- mk_triangle(); bad1$isoyearweek_reporting[1] <- "2019-52"
  expect_error(csfmt_reporting_triangle_v3(bad1, id_cols = ID), "before reference")

  bad2 <- mk_triangle(); bad2$numerator[1] <- -1
  expect_error(csfmt_reporting_triangle_v3(bad2, id_cols = ID), "negative")
})

test_that("reshape builds a reference x delay matrix with zeros filled", {
  tri <- csfmt_reporting_triangle_v3(mk_triangle(), id_cols = ID)
  rt <- reporting_triangle_matrix(tri, max_delay = 3)
  expect_length(rt, 1)
  m <- rt[[1]]$mat
  expect_equal(dim(m), c(3, 3))                 # 3 reference weeks x 3 delays
  expect_equal(rt[[1]]$reference, c("2020-01", "2020-02", "2020-03"))
  # 2020-01: delay0=5, delay1=2, delay2=0
  expect_equal(as.numeric(m[1, ]), c(5, 2, 0))
  # 2020-02: delay0=7, delay1=1, delay2=0
  expect_equal(as.numeric(m[2, ]), c(7, 1, 0))
  # 2020-03: delay0=4 (only just reported), rest 0
  expect_equal(as.numeric(m[3, ]), c(4, 0, 0))
})

test_that("reshape completes the reference axis (interior zero-case week)", {
  # reference weeks 2020-01 and 2020-03 have cases; 2020-02 has none -> must still
  # appear as a contiguous zero row, or the nowcast truncation logic breaks.
  tri_dt <- data.table::data.table(
    indicator = "flu", location = "nation", age = "total", sex = "total",
    isoyearweek_reference = c("2020-01", "2020-03"),
    isoyearweek_reporting = c("2020-01", "2020-03"),
    numerator             = c(5, 4))
  tri <- csfmt_reporting_triangle_v3(tri_dt, id_cols = ID)
  rt <- reporting_triangle_matrix(tri, max_delay = 3)
  m <- rt[[1]]

  expect_equal(m$reference, c("2020-01", "2020-02", "2020-03"))   # gap filled
  expect_equal(as.numeric(m$mat[2, ]), c(0, 0, 0))                # zero-case week
})
