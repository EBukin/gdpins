# test-name-resolution.R — the name-resolution ladder, glob/listing mode, and
# the objects-vs-paths rule. Uses new_fake_raw_conn()/new_fake_board() (no
# network). See the `raw-connection` topic for the specification these pin down.

# ── Fixtures ──────────────────────────────────────────────────────────────────

# A connection with a deliberately awkward shape: a flat file, a file nested
# deeper than raw_ls()'s default depth = 2, and two files sharing a basename.
fx_ladder_conn <- function() {
  conn <- new_fake_raw_conn("drive_local")
  gdpins_raw_put_object(conn, fx_plain_tbl(), "cars.csv")
  gdpins_raw_put_object(conn, list(v = 1L), "sub/sub/folder/deep.rds")
  gdpins_raw_put_object(conn, fx_plain_tbl(), "sub/nested.csv")
  conn
}

fx_ladder_board <- function() {
  board <- new_fake_board(config = "drive_cache_local", name = "probe")
  suppressMessages(gdpins_pin_write(board, mtcars, "cars", format = "rds"))
  suppressMessages(gdpins_pin_write(board, iris, "flowers", format = "rds"))
  board
}

# ── Raw ladder: rung 1 (exact path) ───────────────────────────────────────────

test_that("rung 1: exact relative path resolves, at any depth", {
  conn <- fx_ladder_conn()
  expect_true(file.exists(gdpins_raw_path(conn, "cars.csv")))
  expect_true(file.exists(gdpins_raw_path(conn, "sub/sub/folder/deep.rds")))
})

# ── Raw ladder: rungs 2/3 (basename) ──────────────────────────────────────────

test_that("rung 2: unique basename resolves silently to the full path", {
  conn <- fx_ladder_conn()
  expect_silent(p <- gdpins_raw_path(conn, "deep.rds"))
  expect_true(file.exists(p))
  expect_match(p, "deep\\.rds$")
})

test_that("rung 3: ambiguous basename errors and lists every full path", {
  conn <- fx_ladder_conn()
  gdpins_raw_put_object(conn, fx_plain_tbl(), "other/nested.csv")
  expect_error(gdpins_raw_path(conn, "nested.csv"), "Ambiguous")
  err <- tryCatch(gdpins_raw_path(conn, "nested.csv"), error = function(e) e)
  msg <- paste(c(conditionMessage(err), err$body), collapse = " ")
  expect_match(msg, "sub/nested.csv", fixed = TRUE)
  expect_match(msg, "other/nested.csv", fixed = TRUE)
})

test_that("rung 3 never auto-resolves an ambiguous name", {
  conn <- fx_ladder_conn()
  gdpins_raw_put_object(conn, fx_plain_tbl(), "other/nested.csv")
  expect_error(gdpins_raw_get(conn, "nested.csv"), "Ambiguous")
})

# ── Raw ladder: rung 4 (case-insensitive) ─────────────────────────────────────

test_that("rung 4: case-insensitive unique match resolves to the real spelling", {
  conn <- fx_ladder_conn()
  p <- gdpins_raw_path(conn, "CARS.CSV")
  # The returned path must carry the on-disk spelling on every platform.
  # file.exists() is case-insensitive on Windows only, so a naive fast path
  # would return ".../CARS.CSV" there and ".../cars.csv" on Linux.
  expect_equal(basename(p), "cars.csv")
  expect_true(file.exists(p))
})

# ── Raw ladder: rungs 5-7 (suggest only) ──────────────────────────────────────

test_that("rung 5: same stem, different extension is suggested, not resolved", {
  conn <- fx_ladder_conn()
  expect_error(gdpins_raw_path(conn, "cars.parquet"), "cars\\.csv")
})

test_that("rung 6: an edit-distance near-miss is suggested, not resolved", {
  conn <- fx_ladder_conn()
  expect_error(gdpins_raw_path(conn, "crs.csv"), "cars\\.csv")
})

test_that("rung 6 does not suggest anything for a distant name", {
  conn <- fx_ladder_conn()
  expect_error(
    gdpins_raw_path(conn, "zzzzzzzzzzqqqqqq.xyz"),
    "List everything"
  )
})

test_that("rung 7: empty connection says so rather than suggesting", {
  conn <- new_fake_raw_conn("drive_local")
  expect_error(gdpins_raw_path(conn, "cars.csv"), "no files")
})

# ── Glob / listing mode ───────────────────────────────────────────────────────

test_that("glob returns a gdpins_raw_listing that is still a tibble", {
  conn <- fx_ladder_conn()
  out  <- gdpins_raw_path(conn, "*")
  expect_s3_class(out, "gdpins_raw_listing")
  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c("name", "is_dir", "size", "mtime", "depth", "local_path", "drive_id",
      "drive_url")
  )
})

test_that("glob recurses to full depth, unlike raw_ls(depth = 2)", {
  conn <- fx_ladder_conn()
  expect_true("sub/sub/folder/deep.rds" %in% gdpins_raw_path(conn, "*")$name)
  # The default raw_ls depth is exactly what listing mode must not inherit.
  expect_false("sub/sub/folder/deep.rds" %in% gdpins_raw_ls(conn)$name)
})

test_that("glob filters by extension across directories", {
  conn <- fx_ladder_conn()
  out  <- gdpins_raw_path(conn, "*.csv")
  expect_true(all(c("cars.csv", "sub/nested.csv") %in% out$name))
  expect_false(any(grepl("\\.rds$", out$name)))
})

test_that("glob listings never contain directories", {
  conn <- fx_ladder_conn()
  expect_false(any(gdpins_raw_path(conn, "*")$is_dir))
})

test_that("glob is case-sensitive on every platform", {
  conn <- new_fake_raw_conn("drive_local")
  gdpins_raw_put_object(conn, fx_plain_tbl(), "CARS.CSV")
  expect_equal(nrow(gdpins_raw_path(conn, "*.csv")), 0L)
  expect_equal(nrow(gdpins_raw_path(conn, "*.CSV")), 1L)
})

test_that("raw_get in listing mode lists, and never reads", {
  conn <- fx_ladder_conn()
  out  <- gdpins_raw_get(conn, "*.csv")
  expect_s3_class(out, "gdpins_raw_listing")
  expect_false(is.data.frame(out) && "mpg" %in% names(out))
})

test_that("raw_remove in listing mode lists, and never deletes", {
  conn <- fx_ladder_conn()
  out  <- gdpins_raw_remove(conn, "*.csv")
  expect_s3_class(out, "gdpins_raw_listing")
  expect_true(file.exists(file.path(conn$local_path, "cars.csv")))
})

test_that("a glob matching nothing returns zero rows, not an error", {
  conn <- fx_ladder_conn()
  expect_equal(nrow(gdpins_raw_path(conn, "*.nosuchext")), 0L)
})

# ── raw_remove: rung 1 only ───────────────────────────────────────────────────

test_that("raw_remove does not auto-resolve a basename onto a real file", {
  conn <- fx_ladder_conn()
  deep <- file.path(conn$local_path, "sub", "sub", "folder", "deep.rds")
  expect_true(file.exists(deep))
  suppressWarnings(try(gdpins_raw_remove(conn, "deep.rds"), silent = TRUE))
  expect_true(file.exists(deep))
})

test_that("raw_remove does not auto-resolve an edit-distance near-miss", {
  conn <- fx_ladder_conn()
  flat <- file.path(conn$local_path, "cars.csv")
  suppressWarnings(try(gdpins_raw_remove(conn, "crs.csv"), silent = TRUE))
  expect_true(file.exists(flat))
})

test_that("raw_remove stays an idempotent no-op on a populated connection", {
  conn <- fx_ladder_conn()
  expect_no_error(gdpins_raw_remove(conn, "missing.csv"))
})

# ── Objects vs paths ──────────────────────────────────────────────────────────

test_that("raw_get refuses an unreadable extension, naming the four formats", {
  conn <- new_fake_raw_conn("drive_local")
  src  <- withr::local_tempfile(fileext = ".gpkg")
  writeLines("x", src)
  gdpins_raw_put_file(conn, src, "layer.gpkg")

  err <- tryCatch(gdpins_raw_get(conn, "layer.gpkg"), error = function(e) e)
  msg <- paste(c(conditionMessage(err), err$body), collapse = " ")
  for (ext in c("rds", "parquet", "geojson", "csv")) {
    expect_match(msg, ext, fixed = TRUE)
  }
  expect_match(msg, "gdpins_raw_path", fixed = TRUE)
})

test_that("raw_path returns a path for an extension raw_get cannot read", {
  conn <- new_fake_raw_conn("drive_local")
  src  <- withr::local_tempfile(fileext = ".gpkg")
  writeLines("x", src)
  gdpins_raw_put_file(conn, src, "layer.gpkg")
  expect_true(file.exists(gdpins_raw_path(conn, "layer.gpkg")))
})

test_that("raw_put_file requires an extension but accepts any of them", {
  conn <- new_fake_raw_conn("drive_local")
  src  <- withr::local_tempfile(fileext = ".tif")
  writeLines("x", src)

  expect_error(gdpins_raw_put_file(conn, src, "noext"), "extension")
  # .tif/.gpkg/.xlsx are not readable as objects, but this verb copies bytes --
  # rejecting them would defeat its purpose.
  expect_no_error(gdpins_raw_put_file(conn, src, "raster.tif"))
  expect_no_error(gdpins_raw_put_file(conn, src, "book.xlsx"))
})

# ── Pin ladder ────────────────────────────────────────────────────────────────

test_that("pin_read resolves an exact name and a case-insensitive one", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  expect_s3_class(gdpins_pin_read(board, "cars"), "data.frame")
  expect_s3_class(gdpins_pin_read(board, "CARS"), "data.frame")
})

test_that("pin_read suggests a near-miss instead of reading the wrong pin", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  expect_error(gdpins_pin_read(board, "car"), "Did you mean")
  expect_error(gdpins_pin_read(board, "car"), "cars")
})

test_that("pin_read suggests the extensionless pin for a stem match", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  expect_error(gdpins_pin_read(board, "cars.csv"), "cars")
})

test_that("pin_read on an empty board says the board is empty", {
  board <- new_fake_board(config = "local_only", name = "empty")
  expect_error(gdpins_pin_read(board, "cars"), "no pins")
})

test_that("pin listing mode returns a gdpins_pin_listing, still a tibble", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  out <- gdpins_pin_read(board, "*")
  expect_s3_class(out, "gdpins_pin_listing")
  expect_s3_class(out, "tbl_df")
  expect_true(all(c("cars", "flowers") %in% out$name))
  expect_equal(gdpins_pin_read(board, "f*")$name, "flowers")
})

# ── gdpins_pin_path ───────────────────────────────────────────────────────────

test_that("pin_path returns a real path while pin_read returns the object", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  p <- gdpins_pin_path(board, "cars")
  expect_type(p, "character")
  expect_true(all(file.exists(p)))
  expect_identical(readRDS(p), mtcars)
  expect_s3_class(gdpins_pin_read(board, "cars"), "data.frame")
})

test_that("pin_path materialises a pin that exists only on Drive", {
  board <- new_fake_board(config = "drive_cache_local", name = "driveonly")
  suppressMessages(
    pins::pin_write(board$drive_board, mtcars, "only_on_drive", type = "rds")
  )
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  expect_true(all(file.exists(gdpins_pin_path(board, "only_on_drive"))))
})

test_that("pin_path returns one path per file for a multi-file pin", {
  board <- fx_ladder_board()
  f1 <- withr::local_tempfile(fileext = ".txt"); writeLines("a", f1)
  f2 <- withr::local_tempfile(fileext = ".txt"); writeLines("b", f2)
  suppressMessages(pins::pin_upload(board$local_board, c(f1, f2), "twofiles"))
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  p <- gdpins_pin_path(board, "twofiles")
  expect_length(p, 2L)
  expect_true(all(file.exists(p)))
})

test_that("pin_path uses the ladder and the glob mode", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  expect_true(all(file.exists(gdpins_pin_path(board, "Cars"))))
  expect_error(gdpins_pin_path(board, "car"), "Did you mean")
  expect_s3_class(gdpins_pin_path(board, "*"), "gdpins_pin_listing")
})

test_that("pin_path validates its inputs", {
  expect_error(gdpins_pin_path(list(), "x"), "gdpins_board")
  board <- new_fake_board(config = "local_only")
  expect_error(gdpins_pin_path(board, ""), "non-empty")
})

# ── Listings ──────────────────────────────────────────────────────────────────

test_that("gdpins_list_pins keeps its columns and gains the listing class", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  out <- gdpins_list_pins(board)
  expect_s3_class(out, "gdpins_pin_listing")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("name", "type", "n_versions", "size", "modified"))
})

test_that("gdpins_raw_ls keeps its columns and gains the listing class", {
  conn <- fx_ladder_conn()
  out  <- gdpins_raw_ls(conn)
  expect_s3_class(out, "gdpins_raw_listing")
  expect_s3_class(out, "tbl_df")
  expect_equal(ncol(out), 8L)
})

test_that("a multi-file pin is listed once, with the total size", {
  board <- fx_ladder_board()
  f1 <- withr::local_tempfile(fileext = ".txt"); writeLines("aaaa", f1)
  f2 <- withr::local_tempfile(fileext = ".txt"); writeLines("bbbb", f2)
  suppressMessages(pins::pin_upload(board$local_board, c(f1, f2), "twofiles"))
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  out <- gdpins_list_pins(board)
  # Regression: meta$file_size is a vector for a multi-file pin, which used to
  # recycle `name` and emit one row per file.
  expect_equal(sum(out$name == "twofiles"), 1L)
  expect_gt(out$size[out$name == "twofiles"], 0)
})

# cli emits cliMessage conditions (stderr), not stdout, so these are messages
# rather than output.
test_that("listing print methods show names only", {
  conn <- fx_ladder_conn()
  expect_message(print(gdpins_raw_path(conn, "*.csv")), "cars.csv")
  expect_message(print(gdpins_raw_path(conn, "*.csv")), "2 files")
  # A listing prints its names, not its eight columns of metadata.
  txt <- capture.output(
    print(gdpins_raw_path(conn, "*.csv")),
    type = "message"
  )
  expect_false(any(grepl("drive_url", txt)))
  expect_false(any(grepl("mtime", txt)))
  expect_true(any(grepl("cars.csv", txt, fixed = TRUE)))
})

test_that("pin listing print shows names only", {
  board <- fx_ladder_board()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE, .package = "gdpins"
  )
  txt <- capture.output(print(gdpins_pin_read(board, "*")), type = "message")
  expect_true(any(grepl("cars", txt, fixed = TRUE)))
  expect_false(any(grepl("n_versions", txt)))
})

test_that("print returns its input invisibly", {
  conn <- fx_ladder_conn()
  x <- gdpins_raw_path(conn, "*.csv")
  expect_identical(suppressMessages(print(x)), x)
})

test_that("an empty listing prints a friendly message", {
  conn <- fx_ladder_conn()
  expect_message(
    print(gdpins_raw_path(conn, "*.nosuchext")),
    "No matching files"
  )
})
