# test-discovery.R — TDD for R/discovery.R (WS7)
# Seeds pins DIRECTLY via pins::pin_write(board$<component>, ...)
# Does not depend on WS3 verbs.

# ── Helpers ───────────────────────────────────────────────────────────────────

# Seed three representative pins into a local_only fake board:
#   plain_pin   — plain tibble, 1 version
#   versioned   — plain tibble, 2 versions
#   sf_pin      — sf-encoded parquet (geometry__3857__), 1 version
make_seeded_board <- function() {
  b   <- new_fake_board("local_only")
  src <- b$local_board

  pins::pin_write(src, fx_plain_tbl(), "plain_pin",  type = "parquet")
  pins::pin_write(src, tibble::tibble(v = 1L), "versioned", type = "rds")
  pins::pin_write(src, tibble::tibble(v = 2L), "versioned", type = "rds")

  sf_tbl <- gdpins_sf_to_parquet(fx_sf_non4326())  # geometry__3857__
  pins::pin_write(src, sf_tbl, "sf_pin", type = "parquet")

  b
}

# ── gdpins_list_pins ──────────────────────────────────────────────────────────

test_that("gdpins_list_pins returns tibble with exact columns", {
  b      <- make_seeded_board()
  result <- gdpins_list_pins(b)

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("name", "type", "n_versions", "size", "modified"))
  expect_type(result$name,       "character")
  expect_type(result$type,       "character")
  expect_type(result$n_versions, "integer")
  expect_type(result$size,       "double")
  expect_s3_class(result$modified, "POSIXct")
})

test_that("gdpins_list_pins returns one row per pin", {
  b      <- make_seeded_board()
  result <- gdpins_list_pins(b)

  expect_equal(nrow(result), 3L)
  expect_setequal(result$name, c("plain_pin", "versioned", "sf_pin"))
})

test_that("gdpins_list_pins reports n_versions correctly", {
  b      <- make_seeded_board()
  result <- gdpins_list_pins(b)

  expect_equal(
    result$n_versions[result$name == "versioned"],
    2L
  )
  expect_equal(
    result$n_versions[result$name == "plain_pin"],
    1L
  )
})

test_that("gdpins_list_pins returns zero-row tibble for empty board", {
  b      <- new_fake_board("local_only")
  result <- gdpins_list_pins(b)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
  expect_named(result, c("name", "type", "n_versions", "size", "modified"))
})

test_that("gdpins_list_pins errors on non-board input", {
  expect_error(
    gdpins_list_pins(list()),
    class = "rlang_error"
  )
})

test_that("gdpins_list_pins reads from local_board in drive_cache config", {
  b   <- new_fake_board("drive_cache")
  src <- b$cache_board  # local-first for drive_cache is cache_board

  pins::pin_write(src, fx_plain_tbl(), "cache_pin", type = "parquet")

  result <- gdpins_list_pins(b)
  expect_equal(result$name, "cache_pin")
})

test_that("gdpins_list_pins reads from local_board in drive_cache_local config", {
  b   <- new_fake_board("drive_cache_local")
  src <- b$local_board  # local-first is local_board

  pins::pin_write(src, fx_plain_tbl(), "local_pin", type = "parquet")
  # Drive + cache are empty; should only see local_pin
  result <- gdpins_list_pins(b)
  expect_equal(result$name, "local_pin")
})

test_that("gdpins_list_pins falls back to drive_board when local and cache are NULL", {
  # Construct a board with only drive_board present (local_board = cache_board = NULL)
  fake_root    <- tempfile("gdpins_drive_only_")
  fs::dir_create(fake_root)
  adapter      <- gdpins_fake_drive(root = fake_root)
  drive_dir    <- file.path(fake_root, "test")
  fs::dir_create(drive_dir)
  drive_board  <- pins::board_folder(drive_dir, versioned = TRUE)
  b <- new_gdpins_board(
    config      = "drive_cache",
    name        = "drive_only",
    drive_board = drive_board,
    cache_board = NULL,
    drive_path  = "test",
    adapter     = adapter,
    versioned   = TRUE
  )
  pins::pin_write(drive_board, fx_plain_tbl(), "drive_pin", type = "parquet")

  result <- gdpins_list_pins(b)
  expect_equal(result$name, "drive_pin")
})

# ── gdpins_pin_info ───────────────────────────────────────────────────────────

test_that("gdpins_pin_info returns gdpins_pin_info class", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  pins::pin_write(src, fx_plain_tbl(), "p1", type = "parquet")

  info <- gdpins_pin_info(b, "p1")
  expect_s3_class(info, "gdpins_pin_info")
})

test_that("gdpins_pin_info reports correct type and n_versions for plain pin", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  pins::pin_write(src, fx_plain_tbl(), "p1", type = "parquet")

  info <- gdpins_pin_info(b, "p1")
  expect_equal(info$type,       "parquet")
  expect_equal(info$n_versions, 1L)
  expect_false(info$is_sf)
  expect_true(is.na(info$crs_epsg))
})

test_that("gdpins_pin_info counts multiple versions correctly", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  pins::pin_write(src, tibble::tibble(v = 1L), "multi", type = "rds")
  pins::pin_write(src, tibble::tibble(v = 2L), "multi", type = "rds")
  pins::pin_write(src, tibble::tibble(v = 3L), "multi", type = "rds")

  info <- gdpins_pin_info(b, "multi")
  expect_equal(info$n_versions, 3L)
  expect_equal(nrow(info$versions), 3L)
})

test_that("gdpins_pin_info reports is_sf=FALSE for rds list pin (non-dataframe)", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  # Write a list (non-dataframe) — stored as rds
  pins::pin_write(src, list(a = 1, b = "x"), "list_pin", type = "rds")

  info <- gdpins_pin_info(b, "list_pin")
  expect_equal(info$type, "rds")
  expect_false(info$is_sf)
  expect_true(is.na(info$crs_epsg))
})

test_that("gdpins_pin_info detects sf CRS for geometry__3857__ pin", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  sf_tbl <- gdpins_sf_to_parquet(fx_sf_non4326())
  pins::pin_write(src, sf_tbl, "sf_pin", type = "parquet")

  info <- gdpins_pin_info(b, "sf_pin")
  expect_true(info$is_sf)
  expect_equal(info$crs_epsg, 3857L)
})

test_that("gdpins_pin_info lineage_name equals the bare pin name", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  pins::pin_write(src, fx_plain_tbl(), "my_data_clean", type = "parquet")

  info <- gdpins_pin_info(b, "my_data_clean")
  expect_equal(info$lineage_name, "my_data_clean")
})

test_that("gdpins_pin_info errors when pin does not exist", {
  b <- new_fake_board("local_only")

  expect_error(
    gdpins_pin_info(b, "nonexistent"),
    class = "rlang_error"
  )
})

test_that("gdpins_pin_info errors on non-board input", {
  expect_error(
    gdpins_pin_info(list(), "name"),
    class = "rlang_error"
  )
})

test_that("gdpins_pin_info errors on bad name arg", {
  b <- new_fake_board("local_only")
  expect_error(gdpins_pin_info(b, ""),    class = "rlang_error")
  expect_error(gdpins_pin_info(b, NULL),  class = "rlang_error")
  expect_error(gdpins_pin_info(b, 1L),    class = "rlang_error")
})

# ── Compact ≤80-col output ────────────────────────────────────────────────────

test_that("print.gdpins_pin_info snapshot for sf pin", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  sf_tbl <- gdpins_sf_to_parquet(fx_sf_non4326())
  pins::pin_write(src, sf_tbl, "sf_pin", type = "parquet")
  info <- gdpins_pin_info(b, "sf_pin")

  # Suppress colour codes and scrub the timestamp so snapshot is stable
  withr::with_options(list(cli.num_colors = 1L), {
    expect_snapshot(
      print(info),
      transform = function(x) gsub("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}", "<datetime>", x)
    )
  })
})

test_that("print.gdpins_pin_info snapshot for plain pin", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  pins::pin_write(src, fx_plain_tbl(), "plain_pin", type = "parquet")
  info <- gdpins_pin_info(b, "plain_pin")

  withr::with_options(list(cli.num_colors = 1L), {
    expect_snapshot(
      print(info),
      transform = function(x) gsub("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}", "<datetime>", x)
    )
  })
})

test_that("print.gdpins_pin_info produces no line wider than 80 chars", {
  b   <- new_fake_board("local_only")
  src <- b$local_board
  sf_tbl <- gdpins_sf_to_parquet(fx_sf_non4326())
  pins::pin_write(src, sf_tbl, "sf_pin_with_long_name_to_test", type = "parquet")
  info <- gdpins_pin_info(b, "sf_pin_with_long_name_to_test")

  # cli writes to the message stream
  out <- capture.output(
    withr::with_options(list(cli.num_colors = 1L), print(info)),
    type = "message"
  )
  # Strip ANSI escape sequences and trailing whitespace before measuring width
  clean <- gsub("\033\\[[^m]*m", "", out)
  clean <- trimws(clean, which = "right")
  expect_gt(length(clean), 0L)
  expect_lte(max(nchar(clean)), 80L)
})
