# test-helpers.R — fixtures and fake harness smoke tests

# ── Fixture tests ─────────────────────────────────────────────────────────────

test_that("fx_plain_tbl() returns a tibble", {
  tbl <- fx_plain_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_gt(nrow(tbl), 0L)
  expect_named(tbl, c("id", "name", "value", "flag"))
})

test_that("fx_list_col_tbl() returns a tibble with a list column", {
  tbl <- fx_list_col_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_true(is.list(tbl$data))
})

test_that("fx_nested_tbl() returns a nested tibble", {
  tbl <- fx_nested_tbl()
  expect_s3_class(tbl, "tbl_df")
  expect_true("data" %in% names(tbl))
  expect_true(is.list(tbl$data))
})

test_that("fx_sf_single() returns an sf with EPSG 4326", {
  obj <- fx_sf_single()
  expect_s3_class(obj, "sf")
  epsg <- sf::st_crs(obj)$epsg
  expect_equal(epsg, 4326L)
  expect_gt(nrow(obj), 0L)
})

test_that("fx_sf_multi_crs() returns sf with >= 2 geometry cols", {
  obj  <- fx_sf_multi_crs()
  expect_s3_class(obj, "sf")
  sfc_cols <- vapply(obj, inherits, logical(1L), "sfc")
  expect_gte(sum(sfc_cols), 2L)
})

test_that("fx_sf_multi_crs() has differing CRS across geometry columns", {
  obj      <- fx_sf_multi_crs()
  sfc_cols <- names(which(vapply(obj, inherits, logical(1L), "sfc")))
  epsg_vals <- vapply(sfc_cols, function(cn) {
    sf::st_crs(obj[[cn]])$epsg
  }, integer(1L))
  expect_gt(length(unique(epsg_vals)), 1L)
})

test_that("fx_sf_non4326() returns sf with non-4326 CRS", {
  obj  <- fx_sf_non4326()
  expect_s3_class(obj, "sf")
  epsg <- sf::st_crs(obj)$epsg
  expect_false(isTRUE(epsg == 4326L))
})

test_that("fx_geojson_path() writes a readable geojson file", {
  path <- fx_geojson_path()
  expect_true(file.exists(path))
  expect_true(grepl("\\.geojson$", path))
  obj <- sf::st_read(path, quiet = TRUE)
  expect_s3_class(obj, "sf")
})

test_that("fx_csv_path() writes a readable csv file", {
  path <- fx_csv_path()
  expect_true(file.exists(path))
  expect_true(grepl("\\.csv$", path))
  tbl <- readr::read_csv(path, show_col_types = FALSE)
  expect_s3_class(tbl, "tbl_df")
})

test_that("fx_output_table() returns a tibble", {
  tbl <- fx_output_table()
  expect_s3_class(tbl, "tbl_df")
  expect_named(tbl, c("region", "n_parcels", "mean_value", "year"))
})

test_that("fx_ggplot() returns a ggplot object", {
  p <- fx_ggplot()
  expect_s3_class(p, "ggplot")
})

# ── Fake board harness tests ──────────────────────────────────────────────────

test_that("new_fake_board('drive_cache') returns a valid gdpins_board", {
  board <- new_fake_board("drive_cache")
  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "drive_cache")
  expect_false(is.null(board$adapter))
  expect_false(is.null(board$drive_board))
  expect_false(is.null(board$cache_board))
  expect_null(board$local_board)
})

test_that("new_fake_board('local_only') returns a valid gdpins_board", {
  board <- new_fake_board("local_only")
  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "local_only")
  expect_false(is.null(board$local_board))
  expect_null(board$drive_board)
  expect_null(board$cache_board)
  expect_null(board$adapter)
})

test_that("new_fake_board('drive_cache_local') returns a valid gdpins_board", {
  board <- new_fake_board("drive_cache_local")
  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "drive_cache_local")
  expect_false(is.null(board$adapter))
  expect_false(is.null(board$drive_board))
  expect_false(is.null(board$cache_board))
  expect_false(is.null(board$local_board))
})

test_that("new_fake_board() boards are backed by real tempdir pins boards", {
  board <- new_fake_board("drive_cache")
  expect_s3_class(board$drive_board, "pins_board")
  expect_s3_class(board$cache_board, "pins_board")
})

test_that("new_fake_board() each call returns a fresh board with distinct dirs", {
  b1 <- new_fake_board("drive_cache")
  b2 <- new_fake_board("drive_cache")
  expect_false(identical(b1$cache_dir, b2$cache_dir))
})

test_that("new_fake_board() accepts versioned = FALSE", {
  board <- new_fake_board("drive_cache", versioned = FALSE)
  expect_false(board$versioned)
})

test_that("new_fake_board() accepts custom name", {
  board <- new_fake_board("local_only", name = "data_clean")
  expect_equal(board$name, "data_clean")
})

# ── Fake raw-conn harness tests ───────────────────────────────────────────────

test_that("new_fake_raw_conn('drive_local') returns a valid gdpins_raw_conn", {
  conn <- new_fake_raw_conn("drive_local")
  expect_s3_class(conn, "gdpins_raw_conn")
  expect_equal(conn$config, "drive_local")
  expect_false(is.null(conn$adapter))
  expect_false(is.null(conn$drive_path))
  expect_false(is.null(conn$local_path))
})

test_that("new_fake_raw_conn('local_only') returns a valid gdpins_raw_conn", {
  conn <- new_fake_raw_conn("local_only")
  expect_s3_class(conn, "gdpins_raw_conn")
  expect_equal(conn$config, "local_only")
  expect_null(conn$adapter)
  expect_null(conn$drive_path)
  expect_false(is.null(conn$local_path))
})

test_that("new_fake_raw_conn() local_path exists as a directory", {
  conn <- new_fake_raw_conn("drive_local")
  expect_true(fs::dir_exists(conn$local_path))
})

test_that("new_fake_raw_conn() each call returns fresh paths", {
  c1 <- new_fake_raw_conn("drive_local")
  c2 <- new_fake_raw_conn("drive_local")
  expect_false(identical(c1$local_path, c2$local_path))
})
