# Naming grammar for csfmt measure columns (v3 cohort).
#
# A measure column name is built from structured components instead of ad-hoc
# paste0/str_extract scattered through every method. The convention is
# self-documenting AND machine-navigable: csfmt_var() constructs, csfmt_parse()
# inverts, q_label()/q_value() map a probability to/from its controlled-vocabulary
# label.
#
# Canonical order:
#   <measure>[_vs_<denom>][_<role>][_<q-coord> | _prob_<level>][_pr<per>][<suffix>]
#
#   role  : observed | nowcasted | forecasted | trend | baseline | status
#   q-coord (distribution): q02x5 ... q97x5   (a probability; see q_label)
#   level   (distribution): prob_<level>      (a categorical/ordinal status level)
#   per     : rate scaling, e.g. pr100
#   suffix  : a unit tag, e.g. _n
#
# The draw axis is never named here -- draws are the columns of the wide ensemble
# matrices, anonymous and exchangeable.

#' Probability -> controlled-vocabulary quantile label
#'
#' `0.025 -> "q02x5"`, `0.5 -> "q50x0"`, `0.975 -> "q97x5"`, `0.005 -> "q00x5"`.
#' Two integer-percent digits, then `x`, then one decimal-percent digit.
#'
#' The format is lossy in two ways. It holds one decimal-percent digit, so a
#' finer probability is rounded (`0.0125 -> "q01x2"`). And it holds exactly two
#' integer-percent digits, so `p = 1` produces the three-digit `"q100x0"`, which
#' [q_value] cannot read back. Keep `p` on the 0.001 grid and strictly below 1.
#' @param p Numeric vector of probabilities in [0, 1].
#' @returns Character vector of quantile labels.
#' @family naming grammar functions
#' @seealso [q_value] reads these labels back, for `p < 1`.
#'   \code{vignette("pipeline", package = "csalert")} calls this function in its
#'   naming-grammar section, and every `_qNNxN` column it prints was labelled by
#'   it.
#' @examples
#' q_label(c(0.025, 0.5, 0.975))
#'
#' # limit 1: a probability finer than one decimal percent is rounded
#' q_value(q_label(0.0125))
#'
#' # limit 2: p = 1 produces a three-digit label q_value() returns NA for
#' q_label(1)
#' q_value(q_label(1))
#' @export
q_label <- function(p) {
  stopifnot(is.numeric(p))
  pct <- p * 100
  intp <- floor(pct + 1e-9)
  dec <- round((pct - intp) * 10)
  carry <- !is.na(dec) & dec == 10
  intp[carry] <- intp[carry] + 1
  dec[carry] <- 0
  out <- sprintf("q%02dx%d", as.integer(intp), as.integer(dec))
  out[is.na(p)] <- NA_character_
  out
}

#' Quantile label -> probability
#'
#' Reads back a label written by [q_label]. The pattern accepted is exactly two
#' integer-percent digits, `x`, then one decimal digit. Any string that does not
#' match returns `NA` rather than erroring.
#'
#' The round trip `q_value(q_label(p))` returns `p` only when `p` is expressible
#' in that format, i.e. a probability on the 0.001 grid below 1. `q_label()`
#' rounds anything finer (`0.0125` becomes `"q01x2"`, which reads back as
#' `0.012`), and `q_label(1)` gives the three-digit `"q100x0"`, which returns
#' `NA`. Every probability the package itself uses is on the grid.
#' @param label Character vector of quantile labels, e.g. "q02x5".
#' @returns Numeric vector of probabilities; `NA` for an unparseable label.
#' @family naming grammar functions
#' @seealso [q_label] writes these labels.
#'   \code{vignette("pipeline", package = "csalert")} calls this function in its
#'   naming-grammar section. It is how generic tooling recovers the probability
#'   behind a `_qNNxN` column.
#' @examples
#' q_value(c("q02x5", "q50x0", "q97x5"))
#'
#' # unparseable labels come back NA, including the three-digit q100x0
#' q_value(c("q100x0", "not_a_label"))
#' @export
q_value <- function(label) {
  stopifnot(is.character(label))
  m <- regmatches(label, regexec("^q([0-9]{2})x([0-9])$", label))
  vapply(
    m,
    function(x) {
      if (length(x) != 3) {
        return(NA_real_)
      }
      (as.numeric(x[2]) + as.numeric(x[3]) / 10) / 100
    },
    numeric(1)
  )
}

#' Construct a csfmt measure column name from components
#' @param measure Character scalar, the measure identity (e.g. "consults_r80").
#' @param denom Optional denominator name; inserts `_vs_<denom>`.
#' @param role Optional statistic role: observed/nowcasted/forecasted/trend/baseline/status.
#' @param q Optional probability for a quantile coordinate (mutually exclusive with `level`).
#' @param level Optional status level for a `prob_<level>` coordinate.
#' @param per Optional rate scaling (e.g. 100 -> `_pr100`).
#' @param suffix Optional unit suffix (e.g. "_n").
#' @returns Character scalar column name.
#' @family naming grammar functions
#' @seealso \code{vignette("pipeline", package = "csalert")}, whose closing
#'   section builds a column name with this function and takes it apart again with
#'   \code{\link{csfmt_parse}}.
#' @examples
#' csfmt_var("numerator", role = "nowcasted", q = 0.5)   # "numerator_nowcasted_q50x0"
#' csfmt_var("consults", denom = "population", per = 100) # a rate column name
#' @export
csfmt_var <- function(
  measure,
  denom = NULL,
  role = NULL,
  q = NULL,
  level = NULL,
  per = NULL,
  suffix = NULL
) {
  stopifnot(is.character(measure), length(measure) == 1L)
  if (!is.null(q) && !is.null(level)) {
    stop("supply `q` or `level`, not both")
  }
  v <- measure
  if (!is.null(denom)) {
    v <- paste0(v, "_vs_", denom)
  }
  if (!is.null(role)) {
    v <- paste0(v, "_", role)
  }
  if (!is.null(q)) {
    v <- paste0(v, "_", q_label(q))
  }
  if (!is.null(level)) {
    v <- paste0(v, "_prob_", level)
  }
  if (!is.null(per)) {
    v <- paste0(v, "_pr", formatC(per, format = "d"))
  }
  if (!is.null(suffix)) {
    v <- paste0(v, suffix)
  }
  v
}

# known role vocabulary, for parsing
.csfmt_roles <- c(
  "observed",
  "nowcasted",
  "forecasted",
  "trend",
  "baseline",
  "status",
  "hlmstatus"
)

#' Parse a csfmt measure column name into components
#'
#' Reads a column name written by [csfmt_var] back into its parts. It strips the
#' trailing coordinates, then a role, then a `_vs_<denom>` segment, and whatever
#' is left is the measure.
#'
#' @section Where it does not invert csfmt_var:
#' The parse is a right-to-left strip against a fixed role vocabulary, so it
#' cannot tell which of several role-looking segments was the role. On the
#' package's own rate name it gets the denominator wrong:
#'
#' \preformatted{
#' csfmt_var("numerator_nowcasted", denom = "denominator_nowcasted", per = 100)
#' #> "numerator_nowcasted_vs_denominator_nowcasted_pr100"
#' csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")$denom
#' #> "denominator"          # the denominator's own "_nowcasted" was eaten as the role
#' }
#'
#' Treat it as reliable for a single-role name such as
#' `numerator_nowcasted_q50x0`. Check the result whenever the measure or the
#' denominator itself ends in a role word.
#' @param varname Character scalar column name.
#' @returns Named list with the components that were present (e.g. `measure`,
#'   `role`, `q`, `denom`, `per`).
#' @family naming grammar functions
#' @seealso [csfmt_var] writes these names.
#'   \code{vignette("pipeline", package = "csalert")}, whose closing section
#'   parses a collapsed median column with this function.
#' @examples
#' csfmt_parse("numerator_nowcasted_q50x0")
#'
#' # the documented limit: a denominator that itself ends in a role word is
#' # truncated, because the role is stripped before the _vs_ segment is read
#' csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")
#' @export
csfmt_parse <- function(varname) {
  stopifnot(is.character(varname), length(varname) == 1L)
  x <- varname
  out <- list()

  # Trailing coordinates (suffix / per / quantile / level) are independent and
  # may appear in either order: csfmt_var() emits q-before-per (canonical), but
  # the ensemble bakes per into a measure base and appends q afterwards
  # (..._pr100_q50x0). Strip whichever coordinate is at the tail, repeatedly,
  # until none match -- order-independent.
  repeat {
    matched <- FALSE
    # suffix (known unit tag): _n
    if (is.null(out$suffix) && grepl("_n$", x)) {
      out$suffix <- "_n"
      x <- sub("_n$", "", x)
      matched <- TRUE
    }
    # per: _pr<digits>
    g <- regmatches(x, regexec("_pr([0-9]+)$", x))[[1]]
    if (is.null(out$per) && length(g) == 2) {
      out$per <- as.integer(g[2])
      x <- sub("_pr[0-9]+$", "", x)
      matched <- TRUE
    }
    # quantile coordinate: _qXXxX
    g <- regmatches(x, regexec("_(q[0-9]{2}x[0-9])$", x))[[1]]
    if (is.null(out$q) && length(g) == 2) {
      out$q <- q_value(g[2])
      x <- sub("_q[0-9]{2}x[0-9]$", "", x)
      matched <- TRUE
    }
    # level coordinate: _prob_<level>
    g <- regmatches(x, regexec("_prob_([a-z0-9]+)$", x))[[1]]
    if (is.null(out$level) && length(g) == 2) {
      out$level <- g[2]
      x <- sub("_prob_[a-z0-9]+$", "", x)
      matched <- TRUE
    }
    if (!matched) break
  }
  # role
  for (r in .csfmt_roles) {
    if (grepl(paste0("_", r, "$"), x)) {
      out$role <- r
      x <- sub(paste0("_", r, "$"), "", x)
      break
    }
  }
  # denominator: _vs_<denom>
  g <- regmatches(x, regexec("_vs_([a-z0-9_]+)$", x))[[1]]
  if (length(g) == 2) {
    out$denom <- g[2]
    x <- sub("_vs_[a-z0-9_]+$", "", x)
  }

  out$measure <- x
  out[c("measure", "denom", "role", "q", "level", "per", "suffix")[
    c("measure", "denom", "role", "q", "level", "per", "suffix") %in% names(out)
  ]]
}

# Structural (non-value) columns: the csfmt unified schema + the time_series_*
# bookkeeping + common identity/observed columns. Everything else is a value
# column carrying meaning in its name.
.csfmt_structural <- c(
  "time_series_id",
  "time_series_internal_id",
  "time_series_label",
  "granularity_time",
  "granularity_geo",
  "country_iso3",
  "location_code",
  "border",
  "age",
  "sex",
  "isoyear",
  "isoweek",
  "isoyearweek",
  "isoquarter",
  "isoyearquarter",
  "season",
  "seasonweek",
  "calyear",
  "calmonth",
  "calyearmonth",
  "date",
  "indicator_tag",
  "original"
)

#' Interpret a dataset's columns via the naming grammar
#'
#' Applies [csfmt_parse] to every value column (everything not in the structural
#' schema) and returns a catalog: one row per column with its parsed components.
#' This makes a dataset self-describing -- generic tooling (QC, collapse,
#' presentation) routes on the catalog instead of hardcoding column names.
#' @param d A data.table / data.frame.
#' @param value_cols Optional columns to interpret; defaults to all non-structural.
#' @returns A data.table: `column, measure, denom, role, q, level, per, suffix,
#'   interpretable` (the last TRUE when a role/quantile/level coordinate was found).
#' @family naming grammar functions
#' @seealso Neither package vignette covers this function. It is the dataset-wide
#'   form of \code{\link{csfmt_parse}}, and is what
#'   \code{\link{compare_results}} uses to find the value columns it should diff.
#' @examples
#' d <- data.table::data.table(
#'   isoyearweek = "2023-01",
#'   numerator_nowcasted_q50x0 = 42,
#'   numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0 = 8.4,
#'   numerator_nowcasted_status_prob_high = 0.3,
#'   a_column_outside_the_grammar = 1
#' )
#'
#' # isoyearweek is structural, so it is not a value column at all; the last
#' # column is a value column the grammar cannot read (interpretable = FALSE)
#' csfmt_interpret(d)
#' @export
csfmt_interpret <- function(d, value_cols = NULL) {
  if (is.null(value_cols)) {
    value_cols <- setdiff(names(d), .csfmt_structural)
  }
  g <- function(p, k, na) {
    v <- p[[k]]
    if (is.null(v)) na else v
  }
  rows <- lapply(value_cols, function(col) {
    p <- csfmt_parse(col)
    data.table::data.table(
      column = col,
      measure = g(p, "measure", NA_character_),
      denom = g(p, "denom", NA_character_),
      role = g(p, "role", NA_character_),
      q = g(p, "q", NA_real_),
      level = g(p, "level", NA_character_),
      per = g(p, "per", NA_integer_),
      suffix = g(p, "suffix", NA_character_)
    )
  })
  out <- data.table::rbindlist(rows)
  if (nrow(out)) {
    out[, interpretable := !is.na(role) | !is.na(q) | !is.na(level)]
  }
  out[]
}
