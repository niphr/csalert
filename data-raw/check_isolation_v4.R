# CHECK_ISOLATION for the v4 files of csalert.
#
# Run it from the package root:
#   Rscript data-raw/check_isolation_v4.R [package dir]
#
# A file R/v4_*.R MUST NOT use a csalert object that is defined outside the
# R/v4_*.R files. The script fails, with exit status 1, on each of these:
#   1. a call of such a function, as in q_label(0.5);
#   2. a call through csalert:: or csalert:::;
#   3. the name of such an object as a string argument of do.call(),
#      match.fun(), get(), get0(), mget(), exists(), getFromNamespace() or
#      getExportedValue(), as in do.call("q_label", list(0.5));
#   4. such an object as a bare symbol anywhere other than in the function
#      position of a call, as in lapply(1, row_mean) or f <- row_mean.
#
# Rule 4 does not apply to a name that the file assigns at top level, because
# that name is a v4 object. Inside a function, rule 4 also does not apply to a
# name that the function, or a function around it, takes as a formal argument
# or assigns. Such a name is a local variable. A name assigned in a different
# function is not local, so lapply(1, row_mean) in one function fails when
# only another function assigns row_mean.

args <- commandArgs(trailingOnly = TRUE)
pkg <- if (length(args)) args[[1]] else "."
files <- list.files(file.path(pkg, "R"), pattern = "[.]R$", full.names = TRUE)
is_v4 <- grepl("^v4_", basename(files))
if (!any(is_v4)) {
  stop("no R/v4_*.R file under ", normalizePath(pkg), call. = FALSE)
}

# The names of the top-level assignments of a file, and which of them are
# functions.
top_level <- function(f) {
  exprs <- parse(f, keep.source = FALSE)
  out <- list(all = character(), fun = character())
  for (e in exprs) {
    head <- if (is.call(e)) e[[1]] else NULL
    is_assign <- is.name(head) && as.character(head) %in% c("<-", "=", "<<-")
    if (!is_assign || !is.name(e[[2]])) {
      next
    }
    nm <- as.character(e[[2]])
    out$all <- c(out$all, nm)
    if (is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))) {
      out$fun <- c(out$fun, nm)
    }
  }
  return(out)
}
defs <- lapply(files[!is_v4], top_level)
outside_fun <- unique(unlist(lapply(defs, `[[`, "fun")))
outside_all <- unique(unlist(lapply(defs, `[[`, "all")))
cat("v4 files:", basename(files[is_v4]), "\n")
cat("functions defined outside v4 files:", length(outside_fun), "\n")
cat("objects defined outside v4 files:", length(outside_all), "\n")

LOOKUP_FUNS <- c(
  "do.call",
  "match.fun",
  "get",
  "get0",
  "mget",
  "exists",
  "getFromNamespace",
  "getExportedValue"
)

# The names that an expression assigns with <-, =, <<- or as a for() loop
# variable. The walk does not enter a nested function, because the names of a
# nested function are local to it.
assigned_names <- function(e) {
  if (is.pairlist(e)) {
    out <- character()
    for (a in as.list(e)) {
      if (!missing(a)) out <- c(out, assigned_names(a))
    }
    return(out)
  }
  if (!is.call(e)) {
    return(character())
  }
  head <- e[[1]]
  hname <- if (is.name(head)) as.character(head) else ""
  if (hname == "function") {
    return(character())
  }
  out <- character()
  if (hname %in% c("<-", "=", "<<-", "for") && is.name(e[[2]])) {
    out <- as.character(e[[2]])
  }
  for (a in as.list(e)) {
    if (!missing(a)) out <- c(out, assigned_names(a))
  }
  return(out)
}

# The local names of one function: its formal arguments, and the names that
# its body or its default values assign.
function_locals <- function(e) {
  return(unique(c(
    names(e[[2]]),
    assigned_names(e[[2]]),
    assigned_names(e[[3]])
  )))
}

# Walk an expression. Report every bare symbol that names an outside object
# and is not in the function position, and every string argument of a
# lookup function that names one.
walk <- function(e, locals, found) {
  if (is.name(e)) {
    nm <- as.character(e)
    if (nzchar(nm) && nm %in% outside_all && !nm %in% locals) {
      found$symbol <- c(found$symbol, nm)
    }
    return(found)
  }
  if (is.pairlist(e)) {
    for (a in as.list(e)) {
      if (!missing(a)) found <- walk(a, locals, found)
    }
    return(found)
  }
  if (!is.call(e)) {
    return(found)
  }
  fn <- e[[1]]
  fname <- if (is.name(fn)) as.character(fn) else ""
  if (fname == "function") {
    # a new scope: add the locals of this function to those around it
    inner <- unique(c(locals, function_locals(e)))
    found <- walk(e[[2]], inner, found)
    return(walk(e[[3]], inner, found))
  }
  if (is.call(fn) && as.character(fn[[1]]) %in% c("::", ":::")) {
    fname <- as.character(fn[[3]])
  }
  if (!is.name(fn)) {
    found <- walk(fn, locals, found)
  }
  argl <- as.list(e)[-1]
  if (fname %in% c("$", "@")) {
    argl <- argl[1]
  }
  if (fname %in% c("::", ":::")) {
    argl <- list()
  }
  for (a in argl) {
    if (missing(a)) {
      next
    }
    if (fname %in% LOOKUP_FUNS && is.character(a) && any(a %in% outside_all)) {
      found$string <- c(found$string, a[a %in% outside_all])
    }
    found <- walk(a, locals, found)
  }
  return(found)
}

fail <- 0
for (f in files[is_v4]) {
  pd <- utils::getParseData(parse(f, keep.source = TRUE))
  calls <- unique(pd$text[pd$token == "SYMBOL_FUNCTION_CALL"])
  if (any(pd$text[pd$token == "SYMBOL_PACKAGE"] == "csalert")) {
    cat("FAIL", basename(f), "calls csalert:: or csalert:::\n")
    fail <- fail + 1
  }
  # Rule 1: a call of an outside function with no pkg:: prefix.
  bare <- pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
  for (i in seq_len(nrow(bare))) {
    nm <- bare$text[i]
    sib <- pd[
      pd$parent == bare$parent[i] & pd$token %in% c("NS_GET", "NS_GET_INT"),
    ]
    if (nrow(sib) == 0 && nm %in% outside_fun) {
      cat("FAIL", basename(f), "line", bare$line1[i], "calls", nm, "\n")
      fail <- fail + 1
    }
  }
  # Rules 3 and 4.
  # The top-level names of the file are v4 objects. Each function adds its own
  # locals when the walk enters it.
  exprs <- parse(f, keep.source = FALSE)
  top <- top_level(f)$all
  found <- list(symbol = character(), string = character())
  for (e in exprs) {
    found <- walk(e, top, found)
  }
  for (nm in unique(found$string)) {
    cat("FAIL", basename(f), "names", nm, "as a string in a lookup call\n")
    fail <- fail + 1
  }
  for (nm in unique(found$symbol)) {
    cat("FAIL", basename(f), "uses", nm, "as a bare symbol\n")
    fail <- fail + 1
  }
  cat(basename(f), "calls:", paste(sort(calls), collapse = " "), "\n")
}
if (fail > 0) {
  cat("CHECK_ISOLATION: FAIL", fail, "\n")
  quit(status = 1)
}
cat("CHECK_ISOLATION: PASS\n")
