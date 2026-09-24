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

#' Write a probability as a quantile label
#'
#' Writes `q`, two integer-percent digits, `x` and one decimal-percent digit, so
#' `0.025` becomes `"q02x5"`.
#'
#' The label loses information in two ways. A finer probability is rounded:
#' `0.0125` becomes `"q01x2"`. And `p = 1` gives `"q100x0"`, which [q_value()]
#' cannot read. Keep `p` on the 0.001 grid and below 1.
#' @param p A numeric vector of probabilities.
#' @returns A character vector of labels, with `NA` for `NA`.
#' @family naming grammar functions
#' @seealso `vignette("pipeline", package = "csalert")`, whose naming-grammar
#'   section shows both limits.
#' @examples
#' q_label(c(0.025, 0.5, 0.975))
#'
#' # limit 1: a probability finer than one decimal percent is rounded
#' q_value(q_label(0.0125))
#'
#' # limit 2: p = 1 gives a three-digit label, and q_value() returns NA for it
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
  return(out)
}

#' Read the probability in a quantile label
#'
#' Reads a label that [q_label()] wrote: `q`, two digits, `x` and one digit. Any
#' other string gives `NA`.
#'
#' `q_value(q_label(p))` returns `p` only for a `p` on the 0.001 grid and below 1.
#' Every probability that the package uses is on that grid.
#' @param label A character vector of labels, for example `"q02x5"`.
#' @returns A numeric vector of probabilities.
#' @family naming grammar functions
#' @seealso `vignette("pipeline", package = "csalert")`, whose naming-grammar
#'   section shows the round trip.
#' @examples
#' q_value(c("q02x5", "q50x0", "q97x5"))
#'
#' # a string that is not a label gives NA, and so does the three-digit q100x0
#' q_value(c("q100x0", "not_a_label"))
#' @export
q_value <- function(label) {
  stopifnot(is.character(label))
  m <- regmatches(label, regexec("^q([0-9]{2})x([0-9])$", label))
  return(vapply(
    m,
    function(x) {
      if (length(x) != 3) {
        return(NA_real_)
      }
      return((as.numeric(x[2]) + as.numeric(x[3]) / 10) / 100)
    },
    numeric(1)
  ))
}

#' Build a measure column name from its parts
#'
#' Joins the parts in the order
#' `<measure>[_vs_<denom>][_<role>][_<q-label> | _prob_<level>][_pr<per>][<suffix>]`.
#' The pipeline names its draw matrices and quantile columns with it, so build a
#' name with it before you look a column up.
#' @param measure The name of the measure, for example `"consults_r80"`.
#' @param denom A denominator. It adds `_vs_<denom>`.
#' @param role A role, for example `"nowcasted"`, `"trend"` or `"status"`. It adds
#'   `_<role>`.
#' @param q A probability. It adds the label from [q_label()]. Give `q` or
#'   `level`, not both.
#' @param level A status level. It adds `_prob_<level>`.
#' @param per A rate scale. `100` adds `_pr100`.
#' @param suffix A unit suffix, added as written, for example `"_n"`.
#' @returns The column name.
#' @family naming grammar functions
#' @seealso `vignette("pipeline", package = "csalert")`, whose naming-grammar
#'   section builds and parses a name.
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
    stop("supply `q` or `level`, not both", call. = FALSE)
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
  return(v)
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

# Strip the trailing coordinates from a variable name, and return both the
# stump and what was found. They are independent and may appear in either
# order: csfmt_var() emits q before per, but the ensemble bakes per into a
# measure base and appends q afterwards (..._pr100_q50x0).
# The trailing coordinates, in the order one pass tries them. Each is
# independent of the others and each may appear at most once.
.csfmt_coordinates <- list(
  list(key = "suffix", pattern = "(_n)$", value = function(g) g),
  list(key = "per", pattern = "_pr([0-9]+)$", value = as.integer),
  list(key = "q", pattern = "_(q[0-9]{2}x[0-9])$", value = q_value),
  list(key = "level", pattern = "_prob_([a-z0-9]+)$", value = function(g) g)
)

csfmt_strip_coordinates <- function(x) {
  out <- list()
  repeat {
    matched <- FALSE
    for (co in .csfmt_coordinates) {
      if (!is.null(out[[co$key]])) {
        next
      }
      g <- regmatches(x, regexec(co$pattern, x))[[1]]
      if (length(g) != 2L) {
        next
      }
      out[[co$key]] <- co$value(g[2])
      x <- sub(co$pattern, "", x)
      matched <- TRUE
    }
    if (!matched) {
      break
    }
  }
  return(list(x = x, out = out))
}


#' Split a measure column name into its parts
#'
#' Reads a name that [csfmt_var()] wrote back into its parts. From the right, it
#' removes a `_n` suffix, a `_pr<per>` scale, a quantile label and a
#' `_prob_<level>` level. It then removes a role and `_vs_<denom>`, and the rest
#' is the measure.
#'
#' The roles it knows are `observed`, `nowcasted`, `forecasted`, `trend`,
#' `baseline`, `status` and `hlmstatus`.
#' @section Where it does not invert csfmt_var:
#' The parse cannot tell which of two role words was the role. On the rate name of
#' the package, it gets the denominator wrong:
#'
#' \preformatted{
#' csfmt_var("numerator_nowcasted", denom = "denominator_nowcasted", per = 100)
#' #> "numerator_nowcasted_vs_denominator_nowcasted_pr100"
#' csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")$denom
#' #> "denominator"   # "_nowcasted" of the denominator was read as the role
#' }
#'
#' The parse is reliable for a name with one role word, such as
#' `numerator_nowcasted_q50x0`. Check the result when the measure or the
#' denominator ends in a role word.
#' @param varname The column name.
#' @returns A named list of the parts that are present: `measure`, `denom`,
#'   `role`, `q`, `level`, `per` and `suffix`, in that order.
#' @family naming grammar functions
#' @seealso `vignette("pipeline", package = "csalert")`, whose naming-grammar
#'   section shows this limit.
#' @examples
#' csfmt_parse("numerator_nowcasted_q50x0")
#'
#' # the limit: the role is removed before the _vs_ part is read, so a
#' # denominator that ends in a role word loses that word
#' csfmt_parse("numerator_nowcasted_vs_denominator_nowcasted_pr100")
#' @export
csfmt_parse <- function(varname) {
  stopifnot(is.character(varname), length(varname) == 1L)
  x <- varname
  out <- list()

  stripped <- csfmt_strip_coordinates(x)
  x <- stripped$x
  out <- stripped$out
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
  return(out[c("measure", "denom", "role", "q", "level", "per", "suffix")[
    c("measure", "denom", "role", "q", "level", "per", "suffix") %in% names(out)
  ]])
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

#' Split every value column name of a table into its parts
#'
#' Runs [csfmt_parse()] on every value column, and returns one row per column.
#' Code can then find a column by its parts.
#'
#' A value column is any column outside a fixed list of 23 structural names.
#' The list includes `location_code`, `age`, `sex`, `isoyearweek`,
#' `indicator_tag`, `original` and the `time_series_*` columns.
#' @param d A data.table or data.frame.
#' @param value_cols The columns to read. `NULL` reads every value column.
#' @returns A data.table with the columns `column`, `measure`, `denom`, `role`,
#'   `q`, `level`, `per`, `suffix` and `interpretable`. `interpretable` is
#'   `TRUE` when the name has a role, a quantile label or a level.
#' @family naming grammar functions
#' @seealso `vignette("pipeline", package = "csalert")`, whose naming-grammar
#'   section shows the grammar. [compare_results()] uses this function.
#' @examples
#' d <- data.table::data.table(
#'   isoyearweek = "2023-01",
#'   numerator_nowcasted_q50x0 = 42,
#'   numerator_nowcasted_vs_denominator_nowcasted_pr100_q50x0 = 8.4,
#'   numerator_nowcasted_status_prob_high = 0.3,
#'   a_column_outside_the_grammar = 1
#' )
#'
#' # isoyearweek is structural, so it has no row. The last column is a value
#' # column that the grammar cannot read, so its interpretable is FALSE.
#' csfmt_interpret(d)
#' @export
csfmt_interpret <- function(d, value_cols = NULL) {
  # NSE column names, declared so R CMD check does not read them as undefined globals
  interpretable <- level <- role <- NULL
  if (is.null(value_cols)) {
    value_cols <- setdiff(names(d), .csfmt_structural)
  }
  g <- function(p, k, na) {
    v <- p[[k]]
    if (is.null(v)) return(na) else return(v)
  }
  rows <- lapply(value_cols, function(col) {
    p <- csfmt_parse(col)
    return(data.table::data.table(
      column = col,
      measure = g(p, "measure", NA_character_),
      denom = g(p, "denom", NA_character_),
      role = g(p, "role", NA_character_),
      q = g(p, "q", NA_real_),
      level = g(p, "level", NA_character_),
      per = g(p, "per", NA_integer_),
      suffix = g(p, "suffix", NA_character_)
    ))
  })
  out <- data.table::rbindlist(rows)
  if (nrow(out)) {
    out[, interpretable := !is.na(role) | !is.na(q) | !is.na(level)]
  }
  return(out[])
}
