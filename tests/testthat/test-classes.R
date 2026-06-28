# test-classes.R — S3 constructor tests

# ── new_gdpins_board ─────────────────────────────────────────────────────────

test_that("new_gdpins_board() returns an object of class gdpins_board", {
  board <- new_gdpins_board(config = "local_only", name = "test")
  expect_s3_class(board, "gdpins_board")
})

test_that("new_gdpins_board() has exact frozen field names", {
  board      <- new_gdpins_board(config = "local_only", name = "data_raw")
  expected   <- c(
    "config", "name", "drive_board", "cache_board", "local_board",
    "cache_dir", "local_dir", "drive_path", "adapter", "versioned"
  )
  expect_named(board, expected)
})

test_that("new_gdpins_board() stores config and name correctly", {
  board <- new_gdpins_board(config = "drive_cache", name = "data_interm")
  expect_equal(board$config, "drive_cache")
  expect_equal(board$name,   "data_interm")
})

test_that("new_gdpins_board() defaults: NULLs and versioned = TRUE", {
  board <- new_gdpins_board(config = "local_only", name = "test")
  expect_null(board$drive_board)
  expect_null(board$cache_board)
  expect_null(board$local_board)
  expect_null(board$cache_dir)
  expect_null(board$local_dir)
  expect_null(board$drive_path)
  expect_null(board$adapter)
  expect_true(board$versioned)
})

test_that("new_gdpins_board() accepts versioned = FALSE", {
  board <- new_gdpins_board(config = "local_only", name = "test", versioned = FALSE)
  expect_false(board$versioned)
})

test_that("new_gdpins_board() accepts all three legal configs", {
  for (cfg in c("local_only", "drive_cache", "drive_cache_local")) {
    board <- new_gdpins_board(config = cfg, name = "x")
    expect_equal(board$config, cfg)
  }
})

test_that("new_gdpins_board() errors on illegal config", {
  expect_error(new_gdpins_board(config = "invalid", name = "test"))
})

test_that("new_gdpins_board() errors on empty name", {
  expect_error(new_gdpins_board(config = "local_only", name = ""))
})

test_that("new_gdpins_board() stores optional fields when supplied", {
  fake_adapter <- gdpins_fake_drive()
  board <- new_gdpins_board(
    config     = "drive_cache",
    name       = "data_raw",
    drive_path = "kazLandEconImpact-data/data-raw",
    cache_dir  = tempfile(),
    adapter    = fake_adapter,
    versioned  = TRUE
  )
  expect_equal(board$drive_path, "kazLandEconImpact-data/data-raw")
  expect_false(is.null(board$adapter))
  expect_s3_class(board$adapter, "gdpins_drive_adapter")
})

# ── new_gdpins_raw_conn ───────────────────────────────────────────────────────

test_that("new_gdpins_raw_conn() returns an object of class gdpins_raw_conn", {
  conn <- new_gdpins_raw_conn(
    config     = "local_only",
    local_path = tempfile()
  )
  expect_s3_class(conn, "gdpins_raw_conn")
})

test_that("new_gdpins_raw_conn() has exact frozen field names", {
  conn     <- new_gdpins_raw_conn(config = "local_only", local_path = tempfile())
  expected <- c("config", "drive_path", "local_path", "adapter")
  expect_named(conn, expected)
})

test_that("new_gdpins_raw_conn() stores config and local_path correctly", {
  lp   <- tempfile()
  conn <- new_gdpins_raw_conn(config = "local_only", local_path = lp)
  expect_equal(conn$config,     "local_only")
  expect_equal(conn$local_path, lp)
})

test_that("new_gdpins_raw_conn() defaults: drive_path and adapter are NULL for local_only", {
  conn <- new_gdpins_raw_conn(config = "local_only", local_path = tempfile())
  expect_null(conn$drive_path)
  expect_null(conn$adapter)
})

test_that("new_gdpins_raw_conn() accepts drive_local config", {
  adapter <- gdpins_fake_drive()
  conn <- new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = "raw-exogenous",
    local_path = tempfile(),
    adapter    = adapter
  )
  expect_equal(conn$config,     "drive_local")
  expect_equal(conn$drive_path, "raw-exogenous")
  expect_s3_class(conn$adapter, "gdpins_drive_adapter")
})

test_that("new_gdpins_raw_conn() errors on illegal config", {
  expect_error(new_gdpins_raw_conn(config = "invalid", local_path = tempfile()))
})

test_that("new_gdpins_raw_conn() errors on empty local_path", {
  expect_error(new_gdpins_raw_conn(config = "local_only", local_path = ""))
})

test_that("new_gdpins_raw_conn() accepts both legal configs", {
  for (cfg in c("drive_local", "local_only")) {
    conn <- new_gdpins_raw_conn(config = cfg, local_path = tempfile())
    expect_equal(conn$config, cfg)
  }
})
