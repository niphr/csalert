# qc_surveillance_data_v1: generic input quality-control checks.
#
# Returns a verdict (ok + reasons); it does NOT control flow or decide policy.
# The CALLER supplies the policy (what `expect_latest` is, whether to run QC at
# all) and acts on the verdict (skip, NA, proceed). This keeps the vetted checks
# shared across surveillance systems while the Norwegian/operational decisions
# (data arrives by today-7, don't publish stale numbers) stay in the caller.

#' Quality-control checks on surveillance input data
#' @param d A data.table of one indicator's data.
#' @param reference_col The reference time column (default "isoyearweek_reference").
#' @param expect_latest Optional: the latest reference period that *should* be
#'   present. If `max(reference) < expect_latest`, the feed is flagged stale.
#' @param min_rows Minimum rows required (default 1).
#' @returns A list: `ok` (logical) and `reasons` (character vector; empty if ok).
#' @seealso Neither package vignette covers input quality control. This function
#'   returns a verdict and nothing else -- the caller decides what to do with it.
#'   \code{\link{qc_week_over_week_v1}} answers a different question, about two
#'   finished runs rather than one input feed.
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
  list(ok = length(reasons) == 0L, reasons = reasons)
}
