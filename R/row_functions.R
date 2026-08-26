row_mean <- function(x, na.rm = FALSE, dims = 1L){
  rowMeans(x, na.rm, dims)
}

row_sd <- function(x, na.rm=FALSE) {
  # Vectorised version of variance filter
  sqrt(rowSums((x - rowMeans(x, na.rm=na.rm))^2, na.rm=na.rm) / (ncol(x) - 1))
}
