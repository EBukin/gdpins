remotes::install_github("r-lib/nanoparquet", ref = "main")
library(nanoparquet)
make_cell <- function(n) {
  tok <- "12345.6789 6543.2109, "
  substr(strrep(tok, ceiling(n / nchar(tok))), 1L, n)
}

big <- data.frame(g = make_cell(2097152L), stringsAsFactors = FALSE) # one ~2 MB cell

# arrow-written -> nanoparquet reads it fine (~130 MB)
fa <- tempfile(fileext = ".parquet")
arrow::write_parquet(big, fa)
str(nanoparquet::read_parquet(fa))

# nanoparquet-written -> nanoparquet read allocates tens of GB and crashes
fn <- tempfile(fileext = ".parquet")
nanoparquet::write_parquet(big, fn)
x <- nanoparquet::read_parquet(fn) # <-- boom
