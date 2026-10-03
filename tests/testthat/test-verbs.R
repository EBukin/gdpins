# test-verbs.R — WS3 tests for gdpins_pin_write + gdpins_pin_read
# Uses new_fake_board() harness (no network).

# ── 1. Fan-out write ──────────────────────────────────────────────────────────

test_that("write to drive_cache lands on exactly drive and local boards", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  gdpins_pin_write(board, fx_plain_tbl(), name = "plain")

  expect_true(pins::pin_exists(board$drive_board, "plain"))
  expect_true(pins::pin_exists(board$local_board, "plain"))
})

test_that("write to drive_only lands on Drive only", {
  board <- new_fake_board(config = "drive_only")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  gdpins_pin_write(board, fx_plain_tbl(), name = "fanout")

  expect_true(pins::pin_exists(board$drive_board, "fanout"))
  expect_null(board$local_board)
})

test_that("write to local_only lands only on local board", {
  board <- new_fake_board(config = "local_only")
  gdpins_pin_write(board, fx_plain_tbl(), name = "local_only_pin")
  expect_true(pins::pin_exists(board$local_board, "local_only_pin"))
  # drive is NULL — just verify board has correct structure
  expect_null(board$drive_board)
})

# ── 2. Local-first read ───────────────────────────────────────────────────────

test_that("read is local-first: prefers local_board over drive", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  # Write different data to each board component directly
  local_tbl  <- tibble::tibble(src = "local")
  drive_tbl  <- tibble::tibble(src = "drive")

  pins::pin_write(board$local_board, local_tbl, name = "src_test", type = "rds")
  pins::pin_write(board$drive_board, drive_tbl, name = "src_test", type = "rds")

  result <- gdpins_pin_read(board, "src_test")
  expect_equal(result$src, "local")
})

test_that("read falls back to drive if not in local", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  drive_tbl <- tibble::tibble(src = "drive")
  pins::pin_write(board$drive_board, drive_tbl, name = "drive_only", type = "rds")

  result <- gdpins_pin_read(board, "drive_only")
  expect_equal(result$src, "drive")
})

test_that("drive_cache read when pin only on Drive returns Drive data", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  drive_tbl <- tibble::tibble(src = "drive")
  pins::pin_write(board$drive_board, drive_tbl, name = "pref_test", type = "rds")

  result <- gdpins_pin_read(board, "pref_test")
  expect_equal(result$src, "drive")
})

# ── 3. Offline write blocked ──────────────────────────────────────────────────

test_that("write to drive board is blocked offline", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )

  expect_error(
    gdpins_pin_write(board, fx_plain_tbl(), name = "blocked"),
    "no internet connection"
  )
})

test_that("write to local_only board is allowed offline (no online check)", {
  board <- new_fake_board(config = "local_only")
  # No mocking needed — local_only never checks online
  expect_no_error(
    gdpins_pin_write(board, fx_plain_tbl(), name = "offline_local")
  )
})

# ── 4. Offline read fallback ──────────────────────────────────────────────────

test_that("read from drive_cache offline and pin in local: returns local value", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  pins::pin_write(board$local_board, tibble::tibble(x = 1), name = "offline_pin", type = "rds")

  # Now go offline
  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )

  result <- gdpins_pin_read(board, "offline_pin")
  expect_equal(result$x, 1L)
})

test_that("[T3] drive_only read offline warns and returns NULL", {
  board <- new_fake_board(config = "drive_only")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  # Only write to drive — there is no local copy on a drive_only board
  pins::pin_write(board$drive_board, tibble::tibble(x = 99), name = "drive_pin", type = "rds")

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )

  expect_warning(
    result <- gdpins_pin_read(board, "drive_pin"),
    "only available on Drive"
  )
  expect_null(result)
})

# ── 5. Format dispatch ────────────────────────────────────────────────────────

test_that("plain tibble auto-detects as parquet and round-trips", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  gdpins_pin_write(board, orig, name = "plain")
  result <- gdpins_pin_read(board, "plain")
  expect_equal(result, orig)
})

test_that("explicit format='rds' is respected", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  gdpins_pin_write(board, orig, name = "forced_rds", format = "rds")
  result <- gdpins_pin_read(board, "forced_rds")
  expect_equal(tibble::as_tibble(result), tibble::as_tibble(orig))
})

test_that("explicit format='parquet' is respected", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  gdpins_pin_write(board, orig, name = "forced_parquet", format = "parquet")
  result <- gdpins_pin_read(board, "forced_parquet")
  expect_equal(result, orig)
})

test_that("format='arrow' is no longer a valid write format", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  expect_error(
    gdpins_pin_write(board, orig, name = "should_not_write", format = "arrow")
  )
})

test_that("pre-existing pins written in the legacy arrow format can still be read", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  # Simulate a pin written before the arrow -> parquet switch by writing
  # directly to the underlying pins board with the legacy type.
  pins::pin_write(board$local_board, orig, name = "legacy_arrow_pin", type = "arrow")

  expect_equal(pins::pin_meta(board$local_board, "legacy_arrow_pin")$type, "arrow")

  result <- gdpins_pin_read(board, "legacy_arrow_pin")
  expect_equal(result, orig)
})

# ── 6. Round-trip fixtures ────────────────────────────────────────────────────

test_that("fx_plain_tbl round-trips", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_plain_tbl()
  gdpins_pin_write(board, orig, name = "plain_rt")
  result <- gdpins_pin_read(board, "plain_rt")
  expect_equal(result, orig)
})

test_that("fx_list_col_tbl round-trips (rds)", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_list_col_tbl()
  gdpins_pin_write(board, orig, name = "list_col_rt")
  result <- gdpins_pin_read(board, "list_col_rt")
  # Compare structure (pins may add attributes)
  expect_equal(nrow(result), nrow(orig))
  expect_equal(result$id, orig$id)
  expect_equal(result$label, orig$label)
  expect_equal(result$data, orig$data)
})

test_that("fx_nested_tbl round-trips (rds)", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_nested_tbl()
  gdpins_pin_write(board, orig, name = "nested_rt")
  result <- gdpins_pin_read(board, "nested_rt")
  expect_equal(nrow(result), nrow(orig))
  expect_equal(result$group, orig$group)
  # Nested data col should be a list
  expect_true(is.list(result$data))
})

test_that("fx_sf_single round-trips with sf class and correct CRS", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_sf_single()
  gdpins_pin_write(board, orig, name = "sf_single_rt")
  result <- gdpins_pin_read(board, "sf_single_rt")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 4326L)
  expect_equal(nrow(result), nrow(orig))
})

test_that("fx_sf_non4326 round-trips with correct CRS (3857)", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_sf_non4326()
  gdpins_pin_write(board, orig, name = "sf_non4326_rt")
  result <- gdpins_pin_read(board, "sf_non4326_rt")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 3857L)
  expect_equal(nrow(result), nrow(orig))
})

test_that("fx_sf_multi_crs round-trips: both geometry columns restored with correct CRS", {
  board <- new_fake_board(config = "local_only")
  orig  <- fx_sf_multi_crs()
  gdpins_pin_write(board, orig, name = "sf_multi_rt")
  result <- gdpins_pin_read(board, "sf_multi_rt")
  expect_s3_class(result, "sf")
  # Both sfc columns should be present
  sfc_cols <- names(result)[vapply(result, inherits, logical(1L), "sfc")]
  expect_length(sfc_cols, 2L)
  # CRSes are correct per column
  expect_equal(sf::st_crs(result$geom_wgs)$epsg, 4326L)
  expect_equal(sf::st_crs(result$geom_web)$epsg, 3857L)
})

# ── 7. sf fan-out write lands on all components ───────────────────────────────

test_that("sf write fans out to drive and local, and read restores sf", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  orig <- fx_sf_single()
  gdpins_pin_write(board, orig, name = "sf_fanout")

  expect_true(pins::pin_exists(board$drive_board, "sf_fanout"))
  expect_true(pins::pin_exists(board$local_board, "sf_fanout"))

  result <- gdpins_pin_read(board, "sf_fanout")
  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 4326L)
})

# ── 8. Input validation ───────────────────────────────────────────────────────

test_that("pin_write errors on non-board input", {
  expect_error(
    gdpins_pin_write(list(), tibble::tibble(), name = "x"),
    "gdpins_board"
  )
})

test_that("pin_read errors on non-board input", {
  expect_error(
    gdpins_pin_read(list(), name = "x"),
    "gdpins_board"
  )
})

test_that("pin_write errors on empty name", {
  board <- new_fake_board(config = "local_only")
  expect_error(
    gdpins_pin_write(board, tibble::tibble(), name = ""),
    "non-empty"
  )
})

test_that("pin_read errors when pin not found in any component", {
  board <- new_fake_board(config = "local_only")
  expect_error(
    gdpins_pin_read(board, "does_not_exist"),
    "not found"
  )
})

test_that("pin_remove deletes across drive_cache board components", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  gdpins_pin_write(board, fx_plain_tbl(), name = "to_remove")
  expect_true(pins::pin_exists(board$drive_board, "to_remove"))
  expect_true(pins::pin_exists(board$local_board, "to_remove"))

  gdpins_pin_remove(board, "to_remove")

  expect_false(pins::pin_exists(board$drive_board, "to_remove"))
  expect_false(pins::pin_exists(board$local_board, "to_remove"))
})

test_that("pin_remove deletes local-only pin", {
  board <- new_fake_board(config = "local_only")
  gdpins_pin_write(board, fx_plain_tbl(), name = "local_pin")

  expect_true(pins::pin_exists(board$local_board, "local_pin"))
  gdpins_pin_remove(board, "local_pin")
  expect_false(pins::pin_exists(board$local_board, "local_pin"))
})

test_that("[T3] pin_remove with pin only on local_board removes it, no error", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  # Write directly to local_board only — Drive never had this pin
  pins::pin_write(board$local_board, fx_plain_tbl(), name = "local_only_remove", type = "rds")

  expect_true(pins::pin_exists(board$local_board, "local_only_remove"))
  expect_no_error(gdpins_pin_remove(board, "local_only_remove"))
  expect_false(pins::pin_exists(board$local_board, "local_only_remove"))
})

test_that("pin_remove ignores missing pin (idempotent no-op)", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  expect_no_error(gdpins_pin_remove(board, "missing_pin"))
})

test_that("pin_remove validates board and name", {
  expect_error(
    gdpins_pin_remove(list(), "x"),
    "gdpins_board"
  )

  board <- new_fake_board(config = "local_only")
  expect_error(
    gdpins_pin_remove(board, ""),
    "non-empty"
  )
})

# ── 9. Versioned vs unversioned ───────────────────────────────────────────────

test_that("versioned board accumulates multiple versions", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  v1 <- tibble::tibble(x = 1L)
  v2 <- tibble::tibble(x = 2L)
  gdpins_pin_write(board, v1, name = "versioned_pin")
  # pins versions are timestamped to whole seconds; without a gap, writes
  # inside the same second sort ambiguously and "latest" can resolve to
  # either one (parquet writes are fast enough to hit this every time).
  Sys.sleep(1.1)
  gdpins_pin_write(board, v2, name = "versioned_pin")
  # Latest version should be v2
  result <- gdpins_pin_read(board, "versioned_pin")
  expect_equal(result$x, 2L)
})

test_that("unversioned board overwrites on re-write", {
  board <- new_fake_board(config = "local_only", versioned = FALSE)
  v1 <- tibble::tibble(x = 1L)
  v2 <- tibble::tibble(x = 2L)
  gdpins_pin_write(board, v1, name = "unversioned_pin")
  gdpins_pin_write(board, v2, name = "unversioned_pin")
  result <- gdpins_pin_read(board, "unversioned_pin")
  expect_equal(result$x, 2L)
})

# ── 10. Additional branch coverage ───────────────────────────────────────────

test_that("pin_write with explicit version parameter completes without error", {
  board <- new_fake_board(config = "local_only")
  gdpins_pin_write(board, fx_plain_tbl(), name = "versioned_write",
                   version = "v001")
  expect_true(pins::pin_exists(board$local_board, "versioned_write"))
})

test_that(".is_sf_like: non-data-frame returns FALSE", {
  expect_false(gdpins:::.is_sf_like(list(a = 1)))
  expect_false(gdpins:::.is_sf_like(1:5))
  expect_false(gdpins:::.is_sf_like(NULL))
})

test_that(".is_sf_like: tibble with sfc col returns TRUE", {
  sf_obj <- fx_sf_single()
  expect_true(gdpins:::.is_sf_like(sf_obj))
})

test_that(".is_sf_like: plain tibble returns FALSE", {
  expect_false(gdpins:::.is_sf_like(fx_plain_tbl()))
})

test_that("pin_read: falls back to drive when local is absent", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  # Write to drive only (not local)
  pins::pin_write(board$drive_board, tibble::tibble(x = 99L), name = "fallback_err", type = "rds")

  result <- gdpins_pin_read(board, "fallback_err")
  expect_equal(result$x, 99L)
})

test_that("pin_read with version parameter works for versioned board", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  v1 <- tibble::tibble(x = 1L)
  v2 <- tibble::tibble(x = 2L)
  gdpins_pin_write(board, v1, name = "ver_read_test")
  # Get the version id
  versions <- pins::pin_versions(board$local_board, "ver_read_test")
  v_id <- versions$version[1]
  # Re-write v2
  gdpins_pin_write(board, v2, name = "ver_read_test")
  # Read specific version
  result <- gdpins_pin_read(board, "ver_read_test", version = v_id)
  expect_equal(result$x, 1L)
})

test_that("pin_read errors on empty name", {
  board <- new_fake_board(config = "local_only")
  expect_error(
    gdpins_pin_read(board, name = ""),
    "non-empty"
  )
})

test_that("pin_read: read tryCatch error handler warns and tries next source", {
  # Test the tryCatch error handler: pin_exists returns TRUE for local,
  # but .read_from_board fails. We mock .read_from_board to throw once.
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  # Write to local and drive with different data
  pins::pin_write(
    board$local_board,
    tibble::tibble(x = "local"),
    name = "err_test", type = "rds"
  )
  pins::pin_write(
    board$drive_board,
    tibble::tibble(x = "drive"),
    name = "err_test", type = "rds"
  )

  # Mock .read_from_board to fail on first call (local), succeed on second (drive)
  call_count <- 0L
  testthat::local_mocked_bindings(
    .read_from_board = function(pins_board, name, version) {
      call_count <<- call_count + 1L
      if (call_count == 1L) stop("simulated read failure")
      pins::pin_read(pins_board, name)
    },
    .package = "gdpins"
  )

  expect_warning(
    result <- gdpins_pin_read(board, "err_test"),
    "Failed to read pin"
  )
  expect_equal(result$x, "drive")
})

# ── 11. T3: drive-only / glob dedupe coverage ────────────────────────────────

test_that("[T3] gdpins_pin_path() on drive_only returns an existing file path", {
  board <- new_fake_board(config = "drive_only")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  gdpins_pin_write(board, fx_plain_tbl(), name = "drive_only_path")

  p <- gdpins_pin_path(board, "drive_only_path")
  expect_type(p, "character")
  expect_true(all(file.exists(p)))
})

test_that("[T3] glob listing on drive_cache dedupes a pin present on both sides", {
  board <- new_fake_board(config = "drive_cache")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  gdpins_pin_write(board, fx_plain_tbl(), name = "dup_pin")

  out <- gdpins_pin_read(board, "*")
  expect_equal(sum(out$name == "dup_pin"), 1L)
})

# ── 12. V3: verifier adversarial coverage ────────────────────────────────────

test_that("[V3] write to drive_only board is blocked offline (no local fallback)", {
  board <- new_fake_board(config = "drive_only")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )

  expect_error(
    gdpins_pin_write(board, fx_plain_tbl(), name = "blocked_drive_only"),
    "no internet connection"
  )
})

test_that("[V3] pin_remove on drive_only deletes the Drive-only pin, no error", {
  board <- new_fake_board(config = "drive_only")
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  gdpins_pin_write(board, fx_plain_tbl(), name = "drive_only_remove")
  expect_true(pins::pin_exists(board$drive_board, "drive_only_remove"))

  expect_no_error(gdpins_pin_remove(board, "drive_only_remove"))

  expect_false(pins::pin_exists(board$drive_board, "drive_only_remove"))
})

test_that("[V3] .pin_sources() orders/filters components correctly across all configs", {
  dc <- new_fake_board(config = "drive_cache")
  expect_identical(names(gdpins:::.pin_sources(dc)), c("local", "drive"))

  do <- new_fake_board(config = "drive_only")
  expect_identical(names(gdpins:::.pin_sources(do)), "drive")
  expect_identical(gdpins:::.pin_sources(do)[["drive"]], do$drive_board)

  lo <- new_fake_board(config = "local_only")
  expect_identical(names(gdpins:::.pin_sources(lo)), "local")
  expect_identical(gdpins:::.pin_sources(lo)[["local"]], lo$local_board)
})
