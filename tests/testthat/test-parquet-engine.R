# test-parquet-engine.R — parquet reader/writer engine selection.
#
# Regression coverage for the nanoparquet read-time memory explosion: a pin
# whose geometry (WKT) column totals ~20 MB across a handful of rows makes
# nanoparquet::read_parquet() allocate tens of GB and crash the session, while
# arrow reads the identical bytes in bounded memory. gdpins therefore reads and
# writes parquet through arrow by default, with a `gdpins.parquet_engine`
# option to fall back to nanoparquet.

# ── Option default ────────────────────────────────────────────────────────────

test_that("gdpins.parquet_engine defaults to arrow", {
  expect_equal(getOption("gdpins.parquet_engine"), "arrow")
})

test_that(".gdpins_parquet_engine resolves default and validates input", {
  expect_equal(gdpins:::.gdpins_parquet_engine(), "arrow")
  expect_equal(gdpins:::.gdpins_parquet_engine("nanoparquet"), "nanoparquet")
  expect_equal(gdpins:::.gdpins_parquet_engine("arrow"), "arrow")
  expect_error(gdpins:::.gdpins_parquet_engine("duckdb"), "arrow")

  withr::local_options(gdpins.parquet_engine = "nanoparquet")
  expect_equal(gdpins:::.gdpins_parquet_engine(), "nanoparquet")
})

# ── File-level read/write helpers ─────────────────────────────────────────────

test_that(".write_parquet_file / .read_parquet_file round-trip via both engines", {
  df <- fx_plain_tbl()

  for (eng in c("arrow", "nanoparquet")) {
    p <- tempfile(fileext = ".parquet")
    gdpins:::.write_parquet_file(df, p, engine = eng)
    expect_true(file.exists(p))

    back_arrow <- gdpins:::.read_parquet_file(p, engine = "arrow")
    back_nano  <- gdpins:::.read_parquet_file(p, engine = "nanoparquet")
    # Engine-agnostic on read: either reader recovers the same data.
    expect_equal(tibble::as_tibble(back_arrow), df)
    expect_equal(tibble::as_tibble(back_nano),  df)
    expect_s3_class(back_arrow, "tbl_df")
  }
})

# ── gdpins_pin_read routes parquet through the arrow reader by default ─────────

test_that("gdpins_pin_read reads parquet via .read_parquet_file (arrow by default)", {
  board <- new_fake_board(config = "local_only")
  # Simulate a stored parquet pin written the legacy way (pins/nanoparquet).
  pins::pin_write(board$local_board, fx_plain_tbl(), name = "p", type = "parquet")

  seen_engine <- NULL
  testthat::local_mocked_bindings(
    .read_parquet_file = function(path, engine = NULL) {
      seen_engine <<- gdpins:::.gdpins_parquet_engine(engine)
      tibble::as_tibble(arrow::read_parquet(path, mmap = FALSE))
    },
    .package = "gdpins"
  )

  result <- gdpins_pin_read(board, "p")
  expect_equal(seen_engine, "arrow")
  expect_equal(result, fx_plain_tbl())
})

test_that("gdpins.parquet_engine = 'nanoparquet' switches the reader", {
  board <- new_fake_board(config = "local_only")
  pins::pin_write(board$local_board, fx_plain_tbl(), name = "p", type = "parquet")
  withr::local_options(gdpins.parquet_engine = "nanoparquet")

  seen_engine <- NULL
  testthat::local_mocked_bindings(
    .read_parquet_file = function(path, engine = NULL) {
      seen_engine <<- gdpins:::.gdpins_parquet_engine(engine)
      tibble::as_tibble(nanoparquet::read_parquet(path))
    },
    .package = "gdpins"
  )

  gdpins_pin_read(board, "p")
  expect_equal(seen_engine, "nanoparquet")
})

# ── gdpins_pin_write writes parquet with arrow (no nanoparquet poison) ─────────

test_that("gdpins_pin_write stores parquet as an arrow-written file pin", {
  board <- new_fake_board(config = "local_only")
  gdpins_pin_write(board, fx_plain_tbl(), name = "plain")

  # Written through pin_upload -> stored as a pins 'file' pin holding a .parquet.
  expect_equal(pins::pin_meta(board$local_board, "plain")$type, "file")

  paths <- pins::pin_download(board$local_board, "plain")
  pq <- paths[grepl("[.]parquet$", paths)]
  expect_length(pq, 1L)

  # The bytes are arrow-written, so nanoparquet can read them back at this
  # (small) scale — i.e. we are not writing a file only arrow can recover.
  back <- nanoparquet::read_parquet(pq[[1]])
  expect_equal(tibble::as_tibble(back), fx_plain_tbl())
})

test_that("round-trip through gdpins verbs is correct under both engines", {
  for (eng in c("arrow", "nanoparquet")) {
    withr::local_options(gdpins.parquet_engine = eng)
    board <- new_fake_board(config = "local_only")

    gdpins_pin_write(board, fx_plain_tbl(), name = "plain")
    expect_equal(gdpins_pin_read(board, "plain"), fx_plain_tbl(),
                 info = paste("engine", eng))

    sf_orig <- fx_sf_single()
    gdpins_pin_write(board, sf_orig, name = "geo")
    got <- gdpins_pin_read(board, "geo")
    expect_s3_class(got, "sf")
    expect_equal(sf::st_crs(got)$epsg, 4326L, info = paste("engine", eng))
    expect_equal(nrow(got), nrow(sf_orig), info = paste("engine", eng))
  }
})

# ── Regression: the actual OOM shape ──────────────────────────────────────────
# Reading a nanoparquet-written pin with ~20 MB of WKT across 16 rows blows the
# nanoparquet reader past tens of GB. Guarded (writes ~20 MB, and on the buggy
# path would exhaust RAM) — opt in with GDPINS_TEST_OOM=1.

test_that("large multi-row WKT parquet reads back without exploding (arrow path)", {
  skip_if_not(nzchar(Sys.getenv("GDPINS_TEST_OOM")),
              "set GDPINS_TEST_OOM=1 to run the memory-explosion regression")
  skip_if_not_installed("nanoparquet")

  board <- new_fake_board(config = "local_only")

  sizes <- c(3024488, 2346980, 2172277, 1858467, 1707160, 1559794, 1487984,
             1371738, 1155667, 1042502, 931663, 920290, 684276, 607485,
             224689, 194542)
  mkstr <- function(n) {
    tok <- "12345.6789 6543.2109, "
    substr(strrep(tok, ceiling(n / nchar(tok))), 1L, n)
  }
  poison <- tibble::tibble(
    adm1id_90         = sprintf("%02d", seq_along(sizes)),
    `geometry__32642__` = vapply(sizes, mkstr, character(1))
  )
  # Write it the *legacy* way: a nanoparquet-authored type="parquet" pin, which
  # is exactly what reproduces the crash when read by nanoparquet.
  pins::pin_write(board$local_board, poison, name = "geom_big", type = "parquet")

  # Default (arrow) engine must read it back correctly and cheaply.
  result <- gdpins_pin_read(board, "geom_big")
  expect_s3_class(result, "sf")
  expect_equal(nrow(result), length(sizes))
})
