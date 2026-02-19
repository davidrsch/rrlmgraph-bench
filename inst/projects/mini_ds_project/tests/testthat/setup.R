library(testthat)
source(file.path(dirname(dirname(getwd())), "R", "data_prep.R"))

# A tiny CSV written to a temp file for each test
make_csv <- function() {
  f <- tempfile(fileext = ".csv")
  write.csv(
    data.frame(
      id = 1:10,
      score = c(3.1, 4.2, 2.8, NA, 5.0, 3.7, 4.4, 2.1, 3.9, 4.8),
      group = rep(c("A", "B"), 5)
    ),
    f,
    row.names = FALSE
  )
  f
}
