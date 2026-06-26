# qc_surveillance_data: generic input quality-control checks.
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
#' @export
qc_surveillance_data <- function(d, reference_col = "isoyearweek_reference",
                                 expect_latest = NULL, min_rows = 1L) {
  reasons <- character(0)

  if (nrow(d) < min_rows) {
    reasons <- c(reasons, "no data (or fewer rows than min_rows)")
  } else {
    if (!reference_col %in% names(d)) {
      reasons <- c(reasons, sprintf("reference column '%s' missing", reference_col))
    } else if (!is.null(expect_latest)) {
      latest <- max(d[[reference_col]], na.rm = TRUE)
      if (latest < expect_latest)
        reasons <- c(reasons, sprintf("latest reference %s < expected %s (feed not updated)",
                                      latest, expect_latest))
    }
  }
  list(ok = length(reasons) == 0L, reasons = reasons)
}
