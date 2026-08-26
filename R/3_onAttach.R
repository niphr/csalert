#' @import data.table ggplot2
.onAttach <- function(libname, pkgname) {
  version <- tryCatch(
    utils::packageDescription("csalert", fields = "Version"),
    warning = function(w) {
      return(1)
    }
  )

  packageStartupMessage(paste0(
    "csalert ",
    version,
    "\n",
    "https://niphr.github.io/csalert/"
  ))
}
