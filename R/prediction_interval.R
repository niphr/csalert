#' Prediction thresholds
#' @param object Object
#' @param newdata New data
#' @param alpha Two-sided alpha (e.g 0.05)
#' @param z Similar to \code{alpha} (e.g. z=1.96 is the same as alpha=0.05)
#' @param ... dots
#' @return A `data.table` with one row per row of `newdata` and the columns
#'   `lower`, `point` and `upper`, giving the two-sided prediction interval and
#'   the point estimate on the response scale.
prediction_interval <- function(object, newdata, alpha = 0.05, z = NULL, ...){
  UseMethod("prediction_interval", object)
}


#' Prediction thresholds
#' @param object Object
#' @param newdata New data
#' @param alpha Two-sided alpha (e.g 0.05)
#' @param z Similar to \code{alpha} (e.g. z=1.96 is the same as alpha=0.05)
#' @param skewness_transform "none", "1/2", "2/3"
#' @param ... dots
#' @return A `data.table` with one row per row of `newdata` and the columns
#'   `lower`, `point` and `upper`, giving the two-sided prediction interval and
#'   the point estimate on the response scale. All three columns are `NA_real_`
#'   if the underlying `stats::predict` call raises a warning or an error.
#' @method prediction_interval glm
#' @export
prediction_interval.glm <- function(object, newdata, alpha = 0.05, z = NULL, skewness_transform = "none", ...){
  stopifnot(object$family$family %in% c("poisson", "quasipoisson"))
  stopifnot(skewness_transform %in% c("none", "1/2", "2/3"))


  tryCatch({
    pred <- stats::predict(object, newdata, type = "response", se.fit = T)

    mu0 <- pred$fit
    phi <- summary(object)$dispersion

    tau <- phi + (pred$se.fit^2) / mu0
    switch(skewness_transform, none = {
      se <- sqrt(mu0 * tau)
      exponent <- 1
    }, `1/2` = {
      se <- sqrt(1 / 4 * tau)
      exponent <- 1 / 2
    }, `2/3` = {
      se <- sqrt(4 / 9 * mu0^(1 / 3) * tau)
      exponent <- 2 / 3
    }, {
      stop("No proper exponent in prediction_interval.glm")
    })

    if (is.null(z)) z <- stats::qnorm(1 - alpha / 2)
    lower <- (mu0^exponent - z * se)^(1 / exponent)
    upper <- (mu0^exponent + z * se)^(1 / exponent)

    return(
      data.table(
        lower = lower,
        point = mu0,
        upper = upper
      )
    )
  },
  warning = function(cond){
    return(
      data.table(
        lower = rep(NA_real_, nrow(newdata)),
        point = rep(NA_real_, nrow(newdata)),
        upper = rep(NA_real_, nrow(newdata))
      )
    )
  },
  error = function(cond){
    return(
      data.table(
        lower = rep(NA_real_, nrow(newdata)),
        point = rep(NA_real_, nrow(newdata)),
        upper = rep(NA_real_, nrow(newdata))
      )
    )
  })
}




