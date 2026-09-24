# qc_surveillance_data_v1: generic input quality-control checks.
#
# Returns a verdict (ok + reasons); it does NOT control flow or decide policy.
# The CALLER supplies the policy (what `expect_latest` is, whether to run QC at
# all) and acts on the verdict (skip, NA, proceed). This keeps the vetted checks
# shared across surveillance systems while the Norwegian/operational decisions
# (data arrives by today-7, don't publish stale numbers) stay in the caller.

#' Check that a surveillance feed has data and is up to date
#'
#' Checks the input of one indicator for too few rows, a missing reference column,
#' and a newest period older than `expect_latest`. It returns a verdict, and the
#' caller decides what to do.
#'
#' The checks run in that order and stop at the first failure, so `reasons` has at
#' most one entry.
#' @param d A data.table with the data of one indicator.
#' @param reference_col The reference-period column.
#' @param expect_latest The newest period that the caller expects, or `NULL` to
#'   skip the check. The check uses `<`, which orders zero-padded `"YYYY-WW"`
#'   strings correctly.
#' @param min_rows The fewest rows that pass.
#' @returns A list with `ok`, `TRUE` when every check passes, and `reasons`, a
#'   character vector that is empty when `ok` is `TRUE`.
#' @family quality control functions
#' @seealso `vignette("pipeline", package = "csalert")`, section 9.
#' @examples
#' d <- data.table::data.table(
#'   isoyearweek_reference = c("2023-01", "2023-02"),
#'   numerator = c(10, 12)
#' )
#'
#' qc_surveillance_data_v1(d)
#'
#' # the feed has not been updated as far as the caller expected
#' qc_surveillance_data_v1(d, expect_latest = "2023-05")
#'
#' # nothing arrived at all
#' qc_surveillance_data_v1(d[0])
#' @export
qc_surveillance_data_v1 <- function(
  d,
  reference_col = "isoyearweek_reference",
  expect_latest = NULL,
  min_rows = 1L
) {
  reasons <- character(0)

  if (nrow(d) < min_rows) {
    reasons <- c(reasons, "no data (or fewer rows than min_rows)")
  } else {
    if (!reference_col %in% names(d)) {
      reasons <- c(
        reasons,
        sprintf("reference column '%s' missing", reference_col)
      )
    } else if (!is.null(expect_latest)) {
      latest <- max(d[[reference_col]], na.rm = TRUE)
      if (latest < expect_latest) {
        reasons <- c(
          reasons,
          sprintf(
            "latest reference %s < expected %s (feed not updated)",
            latest,
            expect_latest
          )
        )
      }
    }
  }
  return(list(ok = length(reasons) == 0L, reasons = reasons))
}
