# Phase 1 discriminator: the reporting triangle carries dates.
#
# Run it with:
#   env NOT_CRAN=true Rscript --vanilla tests/manual/phase1_triangle.R
#
# The script prints one line per check. It runs every check before it stops, so
# one run names every broken invariant. It stops with a non-zero exit status if
# any check fails.
#
# Rscript --vanilla -f <file> segfaults on this machine (R 4.4.2, Windows).
# Pass the path as a positional argument, as above.

args <- commandArgs(trailingOnly = FALSE)
this_file <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
if (length(this_file) == 0) {
  this_file <- "tests/manual/phase1_triangle.R"
}
pkg_root <- normalizePath(
  file.path(dirname(this_file[1]), "..", ".."),
  winslash = "/"
)
pkgload::load_all(pkg_root, quiet = TRUE)

failures <- character(0)

check <- function(label, ok, detail = "") {
  if (isTRUE(ok)) {
    cat("PASS [", label, "]\n", sep = "")
  } else {
    cat("FAIL [", label, "] ", detail, "\n", sep = "")
    failures <<- c(failures, label)
  }
  return(invisible(isTRUE(ok)))
}

# ---- the renamed API exists ------------------------------------------------
# These two are red on the pre-phase tree, where the argument is max_delay and
# the reporting axis is an ISO week.
reporting_default <- formals(csalert::csfmt_reporting_triangle_v3)$reporting_col
check(
  "formals-reporting-date",
  identical(reporting_default, "reporting_date"),
  paste0("reporting_col default is ", deparse(reporting_default))
)
matrix_formals <- names(formals(csalert::reporting_triangle_matrix))
check(
  "formals-max-delay-days",
  "max_delay_days" %in% matrix_formals,
  paste0("formals are ", paste(matrix_formals, collapse = ", "))
)

# ---- fixtures --------------------------------------------------------------
ID <- c("indicator_tag", "location_code", "age", "sex")
cal <- cstime::dates_by_isoyearweek
week <- "2026-01"
monday <- as.Date(cal$mon[match(week, cal$isoyearweek)])

# one reference week, 35 consecutive daily reports, one count each
daily <- data.table::data.table(
  indicator_tag = "x",
  location_code = "nation",
  age = "total",
  sex = "total",
  isoyearweek_reference = week,
  reporting_date = monday + 0:34,
  numerator = 1L
)

why <- ""
tri <- tryCatch(
  csfmt_reporting_triangle_v3(daily, id_cols = ID),
  error = function(e) {
    why <<- conditionMessage(e)
    NULL
  }
)
mat <- NULL
if (!is.null(tri)) {
  mat <- tryCatch(
    reporting_triangle_matrix(tri, max_delay_days = 35)[[1]]$mat,
    error = function(e) {
      why <<- conditionMessage(e)
      NULL
    }
  )
}

# ---- 1. one column per delay day -------------------------------------------
check(
  "column-count",
  !is.null(mat) && identical(ncol(mat), 35L),
  if (is.null(mat)) paste0("no matrix: ", why) else paste0("ncol = ", ncol(mat))
)

# ---- 2. delay day 34 is inside a 35 day horizon ----------------------------
check(
  "day-34-inside",
  !is.null(mat) && isTRUE(sum(mat) == 35L),
  if (is.null(mat)) paste0("no matrix: ", why) else paste0("sum = ", sum(mat))
)

# ---- 3. a report on the reference Monday has delay 0 -----------------------
# distinct counts on days 0, 1 and 2, so a week start off by one day moves a
# different count into column "0"
monday_first <- data.table::data.table(
  indicator_tag = "x",
  location_code = "nation",
  age = "total",
  sex = "total",
  isoyearweek_reference = week,
  reporting_date = monday + 0:2,
  numerator = c(10L, 20L, 30L)
)

why2 <- ""
tri2 <- tryCatch(
  csfmt_reporting_triangle_v3(monday_first, id_cols = ID),
  error = function(e) {
    why2 <<- conditionMessage(e)
    NULL
  }
)
mat2 <- NULL
if (!is.null(tri2)) {
  mat2 <- tryCatch(
    reporting_triangle_matrix(tri2, max_delay_days = 7)[[1]]$mat,
    error = function(e) {
      why2 <<- conditionMessage(e)
      NULL
    }
  )
}
check(
  "delay-zero",
  !is.null(mat2) && isTRUE(mat2[1, "0"] == 10L),
  if (is.null(mat2)) {
    paste0("no matrix: ", why2)
  } else {
    paste0("row 1 = ", paste(mat2[1, ], collapse = ","))
  }
)

# ---- 4. the as-of boundary is a Date ---------------------------------------
as_of <- attr(tri, "as_of")
check(
  "as-of-date",
  inherits(as_of, "Date") && identical(class(as_of), "Date"),
  paste0("class = ", paste(class(as_of), collapse = "/"))
)

# ---- 5. every non-Date reporting column errors -----------------------------
# IDate is the one an inherits(x, "Date") check lets through, so each of the
# four types is tested on its own.
types <- list(
  character = format(monday + 0:2),
  numeric = as.numeric(monday + 0:2),
  factor = factor(format(monday + 0:2)),
  IDate = data.table::as.IDate(monday + 0:2)
)
for (nm in names(types)) {
  bad <- data.table::copy(monday_first)
  data.table::set(bad, j = "reporting_date", value = types[[nm]])
  got <- tryCatch(
    {
      csfmt_reporting_triangle_v3(bad, id_cols = ID)
      "ACCEPTED, no error"
    },
    error = function(e) conditionMessage(e)
  )
  check(
    paste0("type-rejection/", nm),
    grepl("must be a Date column", got, fixed = TRUE),
    paste0("got: ", got)
  )
}

if (length(failures) > 0) {
  stop(
    "phase1 discriminator FAILED: ",
    paste(failures, collapse = ", "),
    call. = FALSE
  )
}
cat("phase1 discriminator: every check passed\n")
