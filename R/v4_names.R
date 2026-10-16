# The names that v4 functions create. A measure name is the caller's, and v4
# adds no role to it. Every name MUST fit a PostgreSQL identifier, which holds
# at most 63 bytes, and two names MUST NOT become equal when PostgreSQL cuts
# them to 63 bytes.

.V4_NAME_MAX_BYTES <- 63L

# The suffixes that the derived measures of v4 use. A base measure name that
# ends in one of them is an error, so that a derived name never collides with
# a base name.
.V4_RESERVED_SUFFIXES <- c(
  "_trend_beta1",
  "_trend_se",
  "_trend_gr",
  "_trend_pinc",
  "_mem",
  "_hlm"
)

# The first `n` bytes of each UTF-8 string, written as hex, so that a cut
# inside a multi-byte character still compares byte by byte.
.v4_first_bytes <- function(x, n) {
  return(vapply(
    enc2utf8(x),
    function(s) {
      b <- charToRaw(s)
      return(paste(as.character(b[seq_len(min(n, length(b)))]), collapse = ""))
    },
    character(1),
    USE.NAMES = FALSE
  ))
}

# Error on a name over 63 bytes in UTF-8, and on two names that are equal in
# their first 63 bytes. Returns `x`, invisibly.
.v4_check_names <- function(x) {
  if (!is.character(x) || anyNA(x)) {
    stop("names must be a character vector with no NA", call. = FALSE)
  }
  bytes <- nchar(enc2utf8(x), type = "bytes")
  long <- x[bytes > .V4_NAME_MAX_BYTES]
  if (length(long)) {
    stop(
      "names longer than ",
      .V4_NAME_MAX_BYTES,
      " bytes: ",
      paste0(
        "'",
        long,
        "' (",
        bytes[bytes > .V4_NAME_MAX_BYTES],
        ")",
        collapse = ", "
      ),
      call. = FALSE
    )
  }
  cut <- .v4_first_bytes(x, .V4_NAME_MAX_BYTES)
  dup <- x[cut %in% cut[duplicated(cut)]]
  if (length(dup)) {
    stop(
      "names equal in their first ",
      .V4_NAME_MAX_BYTES,
      " bytes: ",
      paste0("'", unique(dup), "'", collapse = ", "),
      call. = FALSE
    )
  }
  return(invisible(x))
}

# Error on a base measure name that ends in a reserved suffix, then check the
# names as .v4_check_names() does. Returns `x`, invisibly.
.v4_check_measure_names <- function(x) {
  .v4_check_names(x)
  pattern <- paste0("(", paste(.V4_RESERVED_SUFFIXES, collapse = "|"), ")$")
  bad <- x[grepl(pattern, x)]
  if (length(bad)) {
    stop(
      "a measure name ends in a reserved suffix (",
      paste(.V4_RESERVED_SUFFIXES, collapse = ", "),
      "): ",
      paste0("'", bad, "'", collapse = ", "),
      call. = FALSE
    )
  }
  return(invisible(x))
}

# A copy of q_label(): `q`, two integer-percent digits, `x`, one
# decimal-percent digit, so 0.025 is "q02x5".
.v4_q_label <- function(p) {
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

# A copy of q_value(): the probability in a label that .v4_q_label() wrote,
# and NA for any other string.
.v4_q_value <- function(label) {
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

# A copy of csfmt_var(), which also checks the name it builds with
# .v4_check_names(). The order is
# <measure>[_vs_<denom>][_<role>][_<q-label> | _prob_<level>][_pr<per>][<suffix>].
.v4_var <- function(
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
    v <- paste0(v, "_", .v4_q_label(q))
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
  .v4_check_names(v)
  return(v)
}

# A copy of the trailing coordinates that csfmt_strip_coordinates() reads,
# in the order one pass tries them.
.V4_COORDINATES <- list(
  list(
    key = "suffix",
    pattern = "(_n)$",
    value = function(g) {
      return(g)
    }
  ),
  list(key = "per", pattern = "_pr([0-9]+)$", value = as.integer),
  list(
    key = "q",
    pattern = "_(q[0-9]{2}x[0-9])$",
    value = function(g) {
      return(.v4_q_value(g))
    }
  ),
  list(
    key = "level",
    pattern = "_prob_([a-z0-9]+)$",
    value = function(g) {
      return(g)
    }
  )
)

# A copy of csfmt_strip_coordinates(): strip the trailing coordinates from a
# name, and return the stump and what was found. Each coordinate may appear
# at most once, and in any order.
.v4_strip_coordinates <- function(x) {
  out <- list()
  repeat {
    matched <- FALSE
    for (co in .V4_COORDINATES) {
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
