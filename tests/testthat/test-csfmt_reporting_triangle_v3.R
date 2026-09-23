# csfmt_reporting_triangle_v3: input contract + ref x delay-day reshape.

ID <- c("indicator", "location", "age", "sex")

# ISO week 2020-01 starts Monday 2019-12-30, 2020-02 starts 2020-01-06 and
# 2020-03 starts 2020-01-13.
mk_triangle <- function() {
  # one series; reference weeks 2020-01..03, reports arriving 0 and 7 days after
  # each reference week starts
  data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = c(
      "2020-01",
      "2020-01",
      "2020-02",
      "2020-02",
      "2020-03"
    ),
    reporting_date = as.Date(c(
      "2019-12-30",
      "2020-01-06",
      "2020-01-06",
      "2020-01-13",
      "2020-01-13"
    )),
    numerator = c(5, 2, 7, 1, 4)
  )
}

test_that("constructor validates and records the as-of boundary as a Date", {
  tri <- csfmt_reporting_triangle_v3(mk_triangle(), id_cols = ID)
  expect_s3_class(tri, "csfmt_reporting_triangle_v3")
  expect_equal(attr(tri, "as_of"), as.Date("2020-01-13"))
  expect_identical(class(attr(tri, "as_of")), "Date")
  expect_true("time_series_id" %in% names(tri))
})

test_that("constructor rejects every non-Date reporting column", {
  # IDate is the one an inherits(x, "Date") check lets through, so all four
  # types are tested on their own.
  bad_types <- list(
    character = c(
      "2019-12-30",
      "2020-01-06",
      "2020-01-06",
      "2020-01-13",
      "2020-01-13"
    ),
    numeric = as.numeric(mk_triangle()$reporting_date),
    factor = factor(format(mk_triangle()$reporting_date)),
    IDate = data.table::as.IDate(mk_triangle()$reporting_date)
  )
  for (nm in names(bad_types)) {
    bad <- mk_triangle()
    data.table::set(bad, j = "reporting_date", value = bad_types[[nm]])
    expect_error(
      csfmt_reporting_triangle_v3(bad, id_cols = ID),
      "must be a Date column",
      info = nm
    )
  }
})

test_that("constructor rejects any missing reporting date, and names the count", {
  # One NA is enough. max() of a Date vector holding an NA is NA, so the as-of
  # boundary would be NA, no reference week would settle, and every nowcast
  # engine would quietly return the observed totals.
  na1 <- mk_triangle()
  na1$reporting_date[2] <- as.Date(NA)
  expect_error(
    csfmt_reporting_triangle_v3(na1, id_cols = ID),
    "has 1 missing value"
  )

  na2 <- mk_triangle()
  na2$reporting_date[c(2, 4)] <- as.Date(NA)
  expect_error(
    csfmt_reporting_triangle_v3(na2, id_cols = ID),
    "has 2 missing value"
  )

  # the clean fixture still builds, so the assertion does not block valid input
  expect_s3_class(
    csfmt_reporting_triangle_v3(mk_triangle(), id_cols = ID),
    "csfmt_reporting_triangle_v3"
  )
})

test_that("rejects reporting before the reference week and negative counts", {
  bad1 <- mk_triangle()
  bad1$reporting_date[1] <- as.Date("2019-12-29") # the Sunday before 2020-01
  expect_error(
    csfmt_reporting_triangle_v3(bad1, id_cols = ID),
    "before reference"
  )

  bad2 <- mk_triangle()
  bad2$numerator[1] <- -1
  expect_error(csfmt_reporting_triangle_v3(bad2, id_cols = ID), "negative")
})

test_that("reshape builds a reference x delay-day matrix with zeros filled", {
  tri <- csfmt_reporting_triangle_v3(mk_triangle(), id_cols = ID)
  rt <- reporting_triangle_matrix(tri, max_delay_days = 15)
  expect_length(rt, 1)
  m <- rt[[1]]$mat
  expect_equal(dim(m), c(3L, 15L)) # 3 reference weeks x 15 delay days
  expect_equal(colnames(m), as.character(0:14))
  expect_equal(rt[[1]]$reference, c("2020-01", "2020-02", "2020-03"))
  # 2020-01: day 0 = 5, day 7 = 2
  expect_equal(as.numeric(m[1, ]), c(5, rep(0, 6), 2, rep(0, 7)))
  # 2020-02: day 0 = 7, day 7 = 1
  expect_equal(as.numeric(m[2, ]), c(7, rep(0, 6), 1, rep(0, 7)))
  # 2020-03: day 0 = 4 (only just reported), rest 0
  expect_equal(as.numeric(m[3, ]), c(4, rep(0, 14)))
  expect_equal(sum(m), 19) # every input count survives the reshape
})

test_that("a report on the reference Monday has delay day 0", {
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = "2026-01",
    # 2026-01 starts Monday 2025-12-29
    reporting_date = as.Date("2025-12-29") + 0:2,
    numerator = c(10, 20, 30)
  )
  tri <- csfmt_reporting_triangle_v3(d, id_cols = ID)
  m <- reporting_triangle_matrix(tri, max_delay_days = 7)[[1]]$mat
  expect_equal(as.numeric(m[1, ]), c(10, 20, 30, 0, 0, 0, 0))
})

test_that("delay day max_delay_days - 1 is the last column, and day 35 counts in it", {
  # 36 consecutive daily reports, one count each, from the reference Monday
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = "2026-01",
    reporting_date = as.Date("2025-12-29") + 0:35,
    numerator = 1
  )
  tri <- csfmt_reporting_triangle_v3(d, id_cols = ID)
  m <- reporting_triangle_matrix(tri, max_delay_days = 35)[[1]]$mat
  expect_equal(ncol(m), 35L) # delay days 0 to 34
  expect_equal(sum(m), 36) # every report is kept
  expect_equal(as.numeric(m[1, "33"]), 1)
  expect_equal(as.numeric(m[1, "34"]), 2) # day 34 and day 35
})

test_that("a report at delay max_delay_days or later counts in the last column", {
  # Reference week 2026-01 is reported at delays 0, 10, 34, 35, 40 and 400 days.
  # The counts are powers of two, so each cell sum names the reports it holds.
  # Week 2025-52 has one report only, 500 days late. That is the shape of a
  # bulk load. A drop of late reports removes the whole week from the matrix.
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = c(rep("2026-01", 6), "2025-52"),
    # 2026-01 starts Monday 2025-12-29, and 2025-52 starts Monday 2025-12-22
    reporting_date = c(
      as.Date("2025-12-29") + c(0, 10, 34, 35, 40, 400),
      as.Date("2025-12-22") + 500
    ),
    numerator = c(1, 2, 4, 8, 16, 32, 64)
  )
  tri <- csfmt_reporting_triangle_v3(d, id_cols = ID)
  rt <- reporting_triangle_matrix(tri, max_delay_days = 35)[[1]]
  m <- rt$mat

  expect_equal(colnames(m), as.character(0:34)) # the delay axis is unchanged
  expect_equal(rt$reference, c("2025-52", "2026-01"))
  expect_equal(sum(m), 127) # no report is lost
  expect_equal(unname(rowSums(m)), c(64, 63))
  # Select rows by reference week, not by position. Under a drop the 2025-52
  # row is absent, and a position index would then error before the
  # assertion could fail.
  w01 <- rt$reference == "2026-01"
  w52 <- rt$reference == "2025-52"
  expect_equal(as.numeric(m[w01, "34"]), 4 + 8 + 16 + 32)
  expect_equal(as.numeric(m[w01, c("0", "10")]), c(1, 2))
  expect_equal(as.numeric(m[w52, "34"]), 64)
})

test_that("a report before the reference Monday stays out of the matrix", {
  # The constructor rejects a negative delay, so move one date after
  # construction: the count of 1000 goes to Sunday 2025-12-28, one day before
  # the reference Monday of 2026-01.
  d <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = "2026-01",
    reporting_date = as.Date("2025-12-29") + c(0, 3, 0),
    numerator = c(5, 2, 1000)
  )
  tri <- csfmt_reporting_triangle_v3(d, id_cols = ID)
  data.table::set(
    tri,
    i = 3L,
    j = "reporting_date",
    value = as.Date("2025-12-28")
  )
  expect_equal(
    as.integer(tri$reporting_date[3] - as.Date("2025-12-29")),
    -1L
  )
  m <- reporting_triangle_matrix(tri, max_delay_days = 7)[[1]]$mat
  expect_equal(as.numeric(m[1, ]), c(5, 0, 0, 2, 0, 0, 0))
})

test_that("reshape completes the reference axis (interior zero-case week)", {
  # reference weeks 2020-01 and 2020-03 have cases; 2020-02 has none -> must still
  # appear as a contiguous zero row, or the nowcast truncation logic breaks.
  tri_dt <- data.table::data.table(
    indicator = "flu",
    location = "nation",
    age = "total",
    sex = "total",
    isoyearweek_reference = c("2020-01", "2020-03"),
    reporting_date = as.Date(c("2019-12-30", "2020-01-13")),
    numerator = c(5, 4)
  )
  tri <- csfmt_reporting_triangle_v3(tri_dt, id_cols = ID)
  rt <- reporting_triangle_matrix(tri, max_delay_days = 15)
  m <- rt[[1]]

  expect_equal(m$reference, c("2020-01", "2020-02", "2020-03")) # gap filled
  expect_equal(as.numeric(m$mat[2, ]), rep(0, 15)) # zero-case week
})
