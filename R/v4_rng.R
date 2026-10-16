# The random-number rule of the v4 methods: no v4 function changes the
# random-number state of the caller.

# Evaluate `expr` after set.seed(seed), then put back the `.Random.seed` that
# the caller had. If the caller had no `.Random.seed`, remove the one that
# set.seed() made. `expr` is a promise, so it runs inside this frame, after
# set.seed(), and on.exit() restores the state also when `expr` errors.
.v4_with_seed <- function(seed, expr) {
  if (
    !is.numeric(seed) ||
      length(seed) != 1L ||
      !is.finite(seed) ||
      seed != round(seed)
  ) {
    stop("`seed` must be one whole number", call. = FALSE)
  }
  env <- globalenv()
  had_seed <- exists(".Random.seed", envir = env, inherits = FALSE)
  old_seed <- NULL
  if (had_seed) {
    old_seed <- get(".Random.seed", envir = env, inherits = FALSE)
  }
  on.exit(.v4_restore_seed(env, had_seed, old_seed), add = TRUE)
  set.seed(seed)
  return(expr)
}

.v4_restore_seed <- function(env, had_seed, old_seed) {
  if (had_seed) {
    assign(".Random.seed", old_seed, envir = env)
  } else if (exists(".Random.seed", envir = env, inherits = FALSE)) {
    rm(".Random.seed", envir = env)
  }
  return(invisible(NULL))
}
