# Phase 4 discriminator: the rename is finished everywhere, and the package is
# green.
#
# Run it with:
#   env NOT_CRAN=true Rscript --vanilla tests/manual/phase4_sweep.R
#
# Rscript --vanilla -f <file> segfaults on this machine (R 4.4.2, Windows).
# `-f` is an R front-end flag, not an Rscript flag. Pass the path positionally.
#
# The script prints one line per check, runs every check before it stops, and
# then stops with a non-zero exit status if any check failed. One run therefore
# names every broken invariant.
#
# THE TWO SEARCH PATTERNS ARE BUILT WITH paste0(), NOT WRITTEN OUT. This file
# lives under tests/, which is one of the paths CHECK 1 and CHECK 2 search. A
# literal would make the script find itself, and both checks would fail forever.
#
# CHECK 3 AND CHECK 4 READ formals(), NOT THE SOURCE. A grep for `max_delay`
# cannot separate a formal from a call site, from a local variable, or from the
# word inside `max_delay_days`. The formals are the contract, so read them.
#
# CHECK 8 RUNS THE SUITE A SECOND TIME, under warnPartialMatchArgs. R matches
# an argument name by PREFIX when nothing matches exactly, so
# `max_delay = 21` binds to a `max_delay_days` formal and returns 21. It is
# silent unless that option is set. A rename therefore leaves every
# partially-matched call site working and unflagged, which is the exact defect
# this rename exists to prevent. Measured 2026-09-22 before the fix: the suite
# reported 0 warnings normally and 282 with the option on.
#
# CHECK 7 RESOLVES A pkgdown TOPIC AGAINST THE Rd ALIASES, not against
# getNamespaceExports(). pkgdown resolves a `contents:` entry against the Rd
# index, and four legitimate entries in _pkgdown.yml are documented topics that
# the package does not export: print.csfmt_ensemble_v3, print.nowcast_calibration,
# prediction_interval and prediction_interval.glm. Checking against the export
# list alone would fail on all four.

args <- commandArgs(trailingOnly = FALSE)
this_file <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
if (length(this_file) == 0) {
  this_file <- "tests/manual/phase4_sweep.R"
}
pkg_root <- normalizePath(
  file.path(dirname(this_file[1]), "..", ".."),
  winslash = "/"
)
pkgload::load_all(pkg_root, quiet = TRUE)

failures <- character(0)

check <- function(label, ok, detail = "") {
  if (isTRUE(ok)) {
    cat("PASS [", label, "] ", detail, "\n", sep = "")
  } else {
    cat("FAIL [", label, "] ", detail, "\n", sep = "")
    failures <<- c(failures, label)
  }
}

# The paths the rename must hold over.
SEARCH_PATHS <- c("R", "tests", "vignettes", "man", "README.md", "_pkgdown.yml")

# THERE IS NO ALLOWLIST. Every hit under SEARCH_PATHS is live and fails the
# check. Round 1 waived one comment line in tests/manual/phase2_as_of.R. That
# comment now names the current engine, so the waiver is gone and both checks
# report waived=0. A waiver does not satisfy an invariant that reads "no file
# contains the old name".

git_grep <- function(pattern) {
  out <- suppressWarnings(system2(
    "git",
    c(
      "-C",
      shQuote(pkg_root),
      "grep",
      "-n",
      "-F",
      "-e",
      shQuote(pattern),
      "--",
      SEARCH_PATHS
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status > 1L) {
    stop(
      "git grep failed with status ",
      status,
      ": ",
      paste(out, collapse = " ")
    )
  }
  return(as.character(out))
}

report_grep <- function(label, pattern) {
  hits <- git_grep(pattern)
  # `waived` is printed and is a constant 0. The field stays so the pass
  # criterion "checks 1 and 2 pass with waived=0" is readable straight off the
  # output, rather than inferred from its absence.
  check(
    label,
    length(hits) == 0L,
    paste0(
      "live=",
      length(hits),
      " waived=",
      0L,
      if (length(hits)) {
        paste0(" :: ", paste(hits, collapse = " | "))
      } else {
        ""
      }
    )
  )
}

# ---- CHECK 1: the old reporting column name is gone ------------------------
report_grep("CHECK 1 no-old-column", paste0("isoyearweek_", "reporting"))

# ---- CHECK 2: the old engine name is gone ----------------------------------
report_grep("CHECK 2 no-old-engine-name", paste0("nowcast_", "quasipoisson"))

# ---- CHECK 3: no exported function has a formal named `max_delay` ----------
# Walk every exported object AND every S3 method the namespace registers, because
# a method's formals are the user-facing argument list for a dispatched call.
ns <- asNamespace("csalert")
exports <- sort(getNamespaceExports("csalert"))
s3_table <- get(".__S3MethodsTable__.", envir = ns)
callables <- list()
for (nm in exports) {
  obj <- get(nm, envir = ns)
  if (is.function(obj)) {
    callables[[nm]] <- obj
  }
}
for (nm in ls(s3_table)) {
  callables[[paste0("S3:", nm)]] <- get(nm, envir = s3_table)
}
offenders <- character(0)
for (nm in names(callables)) {
  fs <- names(formals(callables[[nm]]))
  if ("max_delay" %in% fs) {
    offenders <- c(offenders, nm)
  }
}
check(
  "CHECK 3 no-max-delay-formal",
  length(offenders) == 0L,
  paste0(
    "checked=",
    length(callables),
    " offenders=",
    if (length(offenders)) paste(offenders, collapse = ",") else "none"
  )
)

# ---- CHECK 4: qc_week_over_week_v1 keeps a WEEK-unit horizon ---------------
# Two differently-named parameters with different units is deliberate. The
# alternative is one name meaning days in one function and weeks in another.
qc_formals <- names(formals(qc_week_over_week_v1))
check(
  "CHECK 4 qc-max-delay-weeks-formal",
  "max_delay_weeks" %in% qc_formals,
  paste0("formals=", paste(qc_formals, collapse = ","))
)

# ---- CHECK 7: every pkgdown topic exists -----------------------------------
# Name the oracle in the OUTPUT, not only in this comment. A reviewer reading
# the run alone must not read the alias oracle as a silent downgrade of an
# export oracle.
cat(
  "ORACLE [CHECK 7] a topic resolves against the \\alias{} entries in man/, ",
  "which is what pkgdown itself resolves against. NOT getNamespaceExports(): ",
  "print.csfmt_ensemble_v3, print.nowcast_calibration, prediction_interval and ",
  "prediction_interval.glm are documented and NOT exported, so an export oracle ",
  "fails on a correct file. Corrected in the brief after round 1.\n",
  sep = ""
)
# (Run before the two slow checks, so a typo in _pkgdown.yml is reported early.)
yml <- yaml::read_yaml(file.path(pkg_root, "_pkgdown.yml"))
topics <- unlist(
  lapply(yml$reference, function(sec) sec$contents),
  use.names = FALSE
)
topics <- topics[
  !grepl(
    "^\\s*(starts_with|ends_with|matches|has_keyword|has_concept|lacks_concepts|contains)\\(",
    topics
  )
]
topics <- trimws(topics)
rd_files <- list.files(
  file.path(pkg_root, "man"),
  pattern = "[.]Rd$",
  full.names = TRUE
)
aliases <- unlist(
  lapply(rd_files, function(f) {
    ln <- readLines(f, warn = FALSE)
    m <- regmatches(ln, regexpr("^\\\\alias\\{.*\\}$", ln))
    return(sub("^\\\\alias\\{(.*)\\}$", "\\1", m))
  }),
  use.names = FALSE
)
missing_topics <- setdiff(topics, aliases)
check(
  "CHECK 7 pkgdown-topic-exists",
  length(missing_topics) == 0L,
  paste0(
    "topics=",
    length(topics),
    " aliases=",
    length(aliases),
    " missing=",
    if (length(missing_topics)) {
      paste(missing_topics, collapse = ",")
    } else {
      "none"
    }
  )
)

# ---- CHECK 5: every Rd example runs ----------------------------------------
# tools::Rd2ex writes nothing for an Rd with no \examples, so the example count
# is smaller than the Rd count. Report both, with the base of each.
# CHECK 8 PIGGYBACKS ON THIS LOOP. A published example is a call site the test
# suite never executes, and R/nowcast_evaluate.R held two of them. Running the
# examples with warnPartialMatchArgs on costs nothing here and closes that gap.
# The option only adds warnings; CHECK 5 reads errors, so its verdict is
# unchanged.
ex_failures <- character(0)
ex_partial <- character(0)
n_with_examples <- 0L
ex_opt <- options(warnPartialMatchArgs = TRUE)
for (f in rd_files) {
  tmp <- tempfile(fileext = ".R")
  tools::Rd2ex(f, out = tmp)
  if (!file.exists(tmp) || length(readLines(tmp, warn = FALSE)) == 0L) {
    next
  }
  n_with_examples <- n_with_examples + 1L
  env <- new.env(parent = globalenv())
  res <- withCallingHandlers(
    tryCatch(
      {
        # An example prints. Swallow that, so one failing example is readable
        # among 34 passing ones.
        utils::capture.output(suppressMessages(source(
          tmp,
          local = env,
          echo = FALSE
        )))
        NULL
      },
      error = function(e) conditionMessage(e)
    ),
    warning = function(w) {
      m <- conditionMessage(w)
      if (grepl("partial argument match", m, fixed = TRUE)) {
        ex_partial <<- c(ex_partial, paste0(basename(f), ": ", m))
      }
      invokeRestart("muffleWarning")
    }
  )
  if (!is.null(res)) {
    ex_failures <- c(ex_failures, paste0(basename(f), ": ", res))
  }
  unlink(tmp)
}
options(ex_opt)
check(
  "CHECK 5 rd-examples-run",
  length(ex_failures) == 0L,
  paste0(
    "rd_files=",
    length(rd_files),
    " with_examples=",
    n_with_examples,
    " failed=",
    length(ex_failures),
    if (length(ex_failures)) {
      paste0(" :: ", paste(ex_failures, collapse = " | "))
    } else {
      ""
    }
  )
)

# ---- CHECK 6: the suite is green, with no warning and no skip --------------
suite <- testthat::test_local(
  pkg_root,
  reporter = "silent",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
sdf <- as.data.frame(suite)
n_failed <- sum(sdf$failed)
n_error <- sum(sdf$error)
n_warning <- sum(sdf$warning)
n_skipped <- sum(sdf$skipped)
check(
  "CHECK 6 suite-green",
  n_failed == 0L && n_error == 0L && n_warning == 0L && n_skipped == 0L,
  paste0(
    "tests=",
    nrow(sdf),
    " failed=",
    n_failed,
    " errors=",
    n_error,
    " warnings=",
    n_warning,
    " skipped=",
    n_skipped
  )
)

# ---- CHECK 8: no argument is matched PARTIALLY -----------------------------
# A SECOND suite run. The option has to be in force for the whole run, so this
# cannot re-read the results of CHECK 6. CHECK 6 runs with the option OFF, which
# is how the package is used; CHECK 8 runs with it ON, which is how the defect
# becomes visible.
old_opt <- options(warnPartialMatchArgs = TRUE)
suite_pm <- testthat::test_local(
  pkg_root,
  reporter = "silent",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
options(old_opt)
pdf_pm <- as.data.frame(suite_pm)
n_pm <- sum(pdf_pm$warning)
# Name the message and the file, so a failure says WHICH partial match and where,
# rather than only that the count is not zero.
pm_msgs <- character(0)
for (r in suite_pm) {
  for (k in r$results) {
    if (inherits(k, "expectation_warning")) {
      pm_msgs <- c(pm_msgs, conditionMessage(k))
    }
  }
}
# Build the detail ONLY when there is something to detail. stats::aggregate()
# errors with "no rows to aggregate" on an empty frame, which is the PASSING
# case, so computing it unconditionally makes the check unable to pass. Found
# by running the clean input, which no red proof would ever have reached.
# The examples were measured in CHECK 5's loop, under the same option.
n_pm_ex <- length(ex_partial)
n_pm_all <- n_pm + n_pm_ex
pm_detail <- ""
if (n_pm > 0L) {
  pm_by_msg <- sort(table(pm_msgs), decreasing = TRUE)
  pm_by_file <- stats::aggregate(
    warning ~ file,
    data = pdf_pm[pdf_pm$warning > 0, c("file", "warning")],
    FUN = sum
  )
  pm_detail <- paste0(
    " :: ",
    paste(pm_by_msg, names(pm_by_msg), sep = " x ", collapse = " | "),
    " :: files ",
    paste(pm_by_file$file, pm_by_file$warning, sep = "=", collapse = ",")
  )
}
if (n_pm_ex > 0L) {
  pm_detail <- paste0(
    pm_detail,
    " :: examples ",
    paste(unique(ex_partial), collapse = " | ")
  )
}
check(
  "CHECK 8 no-partial-matching",
  n_pm_all == 0L,
  paste0(
    "suite_tests=",
    nrow(pdf_pm),
    " suite_warnings=",
    n_pm,
    " rd_examples=",
    n_with_examples,
    " example_warnings=",
    n_pm_ex,
    " total=",
    n_pm_all,
    pm_detail
  )
)

cat("\n---- phase4 sweep summary ----\n")
cat("failed checks: ", length(failures), "\n", sep = "")
if (length(failures) > 0) {
  stop(
    "phase4 sweep FAILED: ",
    paste(failures, collapse = "; "),
    call. = FALSE
  )
}
cat("phase4 sweep PASSED\n")
