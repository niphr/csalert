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
#' @param p Numeric vector of probabilities in [0, 1].
#' @returns Character vector of quantile labels.
#' @export
q_label <- function(p) {
  stopifnot(is.numeric(p))
  pct  <- p * 100
  intp <- floor(pct + 1e-9)
  dec  <- round((pct - intp) * 10)
  carry <- !is.na(dec) & dec == 10
  intp[carry] <- intp[carry] + 1
  dec[carry]  <- 0
  out <- sprintf("q%02dx%d", as.integer(intp), as.integer(dec))
  out[is.na(p)] <- NA_character_
  out
}

#' Quantile label -> probability (inverse of [q_label])
#' @param label Character vector of quantile labels, e.g. "q02x5".
#' @returns Numeric vector of probabilities.
#' @export
q_value <- function(label) {
  stopifnot(is.character(label))
  m <- regmatches(label, regexec("^q([0-9]{2})x([0-9])$", label))
  vapply(m, function(x) {
    if (length(x) != 3) return(NA_real_)
    (as.numeric(x[2]) + as.numeric(x[3]) / 10) / 100
  }, numeric(1))
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
#' @export
csfmt_var <- function(measure, denom = NULL, role = NULL, q = NULL,
                      level = NULL, per = NULL, suffix = NULL) {
  stopifnot(is.character(measure), length(measure) == 1L)
  if (!is.null(q) && !is.null(level)) stop("supply `q` or `level`, not both")
  v <- measure
  if (!is.null(denom))  v <- paste0(v, "_vs_", denom)
  if (!is.null(role))   v <- paste0(v, "_", role)
  if (!is.null(q))      v <- paste0(v, "_", q_label(q))
  if (!is.null(level))  v <- paste0(v, "_prob_", level)
  if (!is.null(per))    v <- paste0(v, "_pr", formatC(per, format = "d"))
  if (!is.null(suffix)) v <- paste0(v, suffix)
  v
}

# known role vocabulary, for parsing
.csfmt_roles <- c("observed", "nowcasted", "forecasted", "trend", "baseline", "status")

#' Parse a csfmt measure column name into components (inverse of [csfmt_var])
#' @param varname Character scalar column name.
#' @returns Named list with the components that were present.
#' @export
csfmt_parse <- function(varname) {
  stopifnot(is.character(varname), length(varname) == 1L)
  x <- varname
  out <- list()

  # suffix (known unit tag): _n
  if (grepl("_n$", x)) { out$suffix <- "_n"; x <- sub("_n$", "", x) }
  # per: _pr<digits>
  g <- regmatches(x, regexec("_pr([0-9]+)$", x))[[1]]
  if (length(g) == 2) { out$per <- as.integer(g[2]); x <- sub("_pr[0-9]+$", "", x) }
  # quantile coordinate: _qXXxX
  g <- regmatches(x, regexec("_(q[0-9]{2}x[0-9])$", x))[[1]]
  if (length(g) == 2) { out$q <- q_value(g[2]); x <- sub("_q[0-9]{2}x[0-9]$", "", x) }
  # level coordinate: _prob_<level>
  g <- regmatches(x, regexec("_prob_([a-z0-9]+)$", x))[[1]]
  if (length(g) == 2) { out$level <- g[2]; x <- sub("_prob_[a-z0-9]+$", "", x) }
  # role
  for (r in .csfmt_roles) {
    if (grepl(paste0("_", r, "$"), x)) { out$role <- r; x <- sub(paste0("_", r, "$"), "", x); break }
  }
  # denominator: _vs_<denom>
  g <- regmatches(x, regexec("_vs_([a-z0-9_]+)$", x))[[1]]
  if (length(g) == 2) { out$denom <- g[2]; x <- sub("_vs_[a-z0-9_]+$", "", x) }

  out$measure <- x
  out[c("measure", "denom", "role", "q", "level", "per", "suffix")[
    c("measure", "denom", "role", "q", "level", "per", "suffix") %in% names(out)]]
}
