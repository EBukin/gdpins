# test-live.R — WS9 live tier (ADR §12)
#
# Runs against a REAL Google Drive folder gated by three skip conditions.
# Safe no-op by default (all tests skipped unless env + network + non-CI).
#
# Env var: GDRIVE_TEST_FOLDER = "1Cd4qBwj1k5M49lU4czlo8ut1b3q0HivB"
#
# Run manually:
#   Rscript --no-init-file -e 'testthat::test_file("tests/testthat/test-live.R")'

# ── Gate helpers ──────────────────────────────────────────────────────────────

.skip_live <- function() {
  testthat::skip_on_ci()
  testthat::skip_if(
    nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")),
    message = "Skipping live tier during R CMD check."
  )
  testthat::skip_if(
    !gdpins_is_online(),
    message = "No internet connection — skipping live tier."
  )
  folder_id <- Sys.getenv("GDRIVE_TEST_FOLDER")
  testthat::skip_if(
    !nzchar(folder_id),
    message = "GDRIVE_TEST_FOLDER not set — skipping live tier."
  )
  invisible(NULL)
}

.live_test_root <- function() {
  # Returns the Drive folder ID of the dedicated test folder.
  Sys.getenv("GDRIVE_TEST_FOLDER")
}

# ── Live board round-trip ─────────────────────────────────────────────────────

test_that("[LIVE] board round-trip: write plain tibble, read back identical", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_cache_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("board-rt-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "live_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  original <- fx_plain_tbl()
  suppressMessages(gdpins_pin_write(board, original, "live_tbl"))
  result   <- gdpins_pin_read(board, "live_tbl")

  expect_equal(result, original)
})

test_that("[LIVE] board round-trip: write sf, read back with CRS intact", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_sf_cache_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("board-sf-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "live_sf",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  sf_obj <- fx_sf_single()
  suppressMessages(gdpins_pin_write(board, sf_obj, "live_sf"))
  result <- gdpins_pin_read(board, "live_sf")

  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 4326L)
  expect_equal(nrow(result), nrow(sf_obj))
})

# ── Live sync round-trip ──────────────────────────────────────────────────────

test_that("[LIVE] sync: local-ahead pin reaches Drive after gdpins_sync", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_sync_cache_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("sync-rt-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "live_sync",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Write directly to cache (simulate offline accumulation)
  suppressMessages(
    pins::pin_write(board$cache_board, fx_plain_tbl(), "sync_pin", type = "parquet")
  )

  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  # The pin should now exist on Drive (verify via Drive board)
  expect_true(pins::pin_exists(board$drive_board, "sync_pin"))
})

# ── Live raw connection round-trip ────────────────────────────────────────────

test_that("[LIVE] raw connection round-trip: put_file then get returns identical", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_raw_local_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("raw-rt-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  csv_src <- fx_csv_path()
  suppressMessages(gdpins_raw_put_file(conn, csv_src, "live_test.csv"))
  result <- suppressMessages(gdpins_raw_get(conn, "live_test.csv"))

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), nrow(fx_plain_tbl()))
})

test_that("[LIVE] raw connection: sf parquet round-trip preserves CRS", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_raw_sf_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("raw-sf-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  sf_obj <- fx_sf_single()
  suppressMessages(gdpins_raw_put_object(conn, sf_obj, "parcels.parquet"))
  result <- suppressMessages(gdpins_raw_get(conn, "parcels.parquet"))

  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 4326L)
})

test_that("[LIVE] raw connection: nested put_object creates missing Drive parents", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_raw_nested_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("raw-nested-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  obj1 <- list(v = 1L)
  obj2 <- list(v = 2L)
  suppressMessages(gdpins_raw_put_object(conn, obj1, "kazsub/00-smoke-test.rds"))
  suppressMessages(gdpins_raw_put_object(conn, obj2, "sub/sub/folder/file.rds"))

  got1 <- suppressMessages(gdpins_raw_get(conn, "kazsub/00-smoke-test.rds", force_refresh = TRUE))
  got2 <- suppressMessages(gdpins_raw_get(conn, "sub/sub/folder/file.rds", force_refresh = TRUE))

  expect_equal(got1, obj1)
  expect_equal(got2, obj2)
})

# ── Sync direction: Drive-ahead ("new computer" case) ─────────────────────────

test_that("[LIVE] sync: drive-ahead pin syncs to cache after from_drive", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_driveahead_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("driveahead-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "driveahead",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Seed Drive directly (bypassing fan-out write) — local cache stays empty
  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "drive_pin", type = "parquet")
  )

  # Status: drive_ahead
  status <- gdpins_board_status(board)
  expect_true(any(status$state == "drive_ahead"))

  # Sync from Drive — should emit "Drive → local" message
  expect_message(
    gdpins_sync(board, direction = "from_drive"),
    regexp = "Drive.*local|local.*Drive",
    ignore.case = TRUE
  )

  # Pin now exists locally
  expect_true(pins::pin_exists(board$cache_board, "drive_pin"))
})

# ── Board status: in_sync and local_ahead ─────────────────────────────────────

test_that("[LIVE] board status: in_sync after fan-out write, local_ahead after cache-only write", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_status_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("status-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "status_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Fan-out write → in_sync
  suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "shared_pin"))
  status_sync <- gdpins_board_status(board)
  shared_row  <- status_sync[status_sync$name == "shared_pin", ]
  expect_equal(shared_row$state, "in_sync")

  # Cache-only write → local_ahead
  suppressMessages(
    pins::pin_write(board$cache_board, fx_output_table(), "local_only_pin", type = "parquet")
  )
  status_local <- gdpins_board_status(board)
  local_row    <- status_local[status_local$name == "local_only_pin", ]
  expect_equal(local_row$state, "local_ahead")
})

# ── Offline accumulation → online reconcile ───────────────────────────────────

test_that("[LIVE] sync: offline cache accumulation reconciles to Drive on sync", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_offline_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("offline-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  # Init board while online
  board <- gdpins_init_board(
    name           = "offline_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Simulate offline accumulation: write to cache board directly
  # (gdpins_pin_write blocks when offline; here we bypass it)
  suppressMessages(
    pins::pin_write(board$cache_board, fx_plain_tbl(), "offline_pin1", type = "parquet")
  )
  suppressMessages(
    pins::pin_write(board$cache_board, fx_output_table(), "offline_pin2", type = "parquet")
  )

  # "Come online" and sync to Drive
  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  # Both pins must now exist on Drive
  expect_true(pins::pin_exists(board$drive_board, "offline_pin1"))
  expect_true(pins::pin_exists(board$drive_board, "offline_pin2"))
})

# ── Prune: single pin ─────────────────────────────────────────────────────────

test_that("[LIVE] prune: gdpins_prune_pin_versions trashes old Drive versions", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_prune_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("prune-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "prune_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Write 3 versions
  suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "multi_ver"))
  Sys.sleep(1)
  suppressMessages(gdpins_pin_write(board, fx_output_table(), "multi_ver"))
  Sys.sleep(1)
  suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "multi_ver"))

  versions_before <- pins::pin_versions(board$drive_board, "multi_ver")
  expect_gte(nrow(versions_before), 2L)

  # Prune to keep = 1
  suppressMessages(
    gdpins_prune_pin_versions(board, "multi_ver", keep = 1, dry_run = FALSE, force = TRUE)
  )

  versions_after <- pins::pin_versions(board$drive_board, "multi_ver")
  expect_equal(nrow(versions_after), 1L)
})

# ── Prune: board-wide ─────────────────────────────────────────────────────────

test_that("[LIVE] prune: gdpins_prune_board_versions cleans all pins", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_prunebd_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("prunebd-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "prunebd_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  # Write 2 versions for 2 pins
  for (i in seq_len(2)) {
    suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "pin_a"))
    suppressMessages(gdpins_pin_write(board, fx_output_table(), "pin_b"))
    if (i < 2) Sys.sleep(1)
  }

  suppressMessages(
    gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE, force = TRUE)
  )

  expect_equal(nrow(pins::pin_versions(board$drive_board, "pin_a")), 1L)
  expect_equal(nrow(pins::pin_versions(board$drive_board, "pin_b")), 1L)
})

# ── Init create-confirm ───────────────────────────────────────────────────────

test_that("[LIVE] init: create=FALSE errors when Drive folder absent", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id  <- .live_test_root()
  adapter  <- gdpins_real_drive(root_id)
  missing  <- paste0("nonexistent-", format(Sys.time(), "%Y%m%dT%H%M%S"))

  # lazy = FALSE: this asserts the create-confirm check itself, which the lazy
  # default defers to first use. See ?`lazy-boards`.
  expect_error(
    gdpins_init_board(
      name           = "missing",
      drive_path     = missing,
      cache_dir      = tempfile(),
      adapter        = adapter,
      create         = FALSE,
      on_discrepancy = "ignore",
      lazy           = FALSE
    ),
    class = "rlang_error"
  )
})

test_that("[LIVE] init: create=TRUE creates Drive folder", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_create_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("create-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "create_test",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore",
    lazy           = FALSE
  )

  expect_true(gd_exists(adapter, test_sub))
  expect_s3_class(board, "gdpins_board")
})

# ── Raw extras ────────────────────────────────────────────────────────────────

test_that("[LIVE] raw put_object: Drive md5 matches local file md5", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_md5_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("rawmd5-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  suppressMessages(gdpins_raw_put_object(conn, fx_plain_tbl(), "tbl.parquet"))

  local_file <- file.path(local_path, "tbl.parquet")
  local_md5  <- unname(tools::md5sum(local_file))
  drive_md5  <- gd_md5(adapter, paste0(test_sub, "/tbl.parquet"))

  expect_equal(local_md5, drive_md5)
})

test_that("[LIVE] raw raw_ls lists uploaded files", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_ls_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("rawls-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  suppressMessages(gdpins_raw_put_file(conn, fx_csv_path(), "file_a.csv"))
  suppressMessages(gdpins_raw_put_file(conn, fx_csv_path(), "file_b.csv"))

  listing <- gdpins_raw_ls(conn, depth = 1)

  expect_s3_class(listing, "tbl_df")
  expect_true("file_a.csv" %in% listing$name)
  expect_true("file_b.csv" %in% listing$name)
})

test_that("[LIVE] raw get with force_refresh re-pulls Drive version", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_refresh_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("refresh-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  original <- fx_plain_tbl()
  suppressMessages(gdpins_raw_put_file(conn, fx_csv_path(), "data.csv"))

  # Corrupt the local cache entry
  writeLines("not,a,valid,csv,file", file.path(local_path, "data.csv"))

  # Without force_refresh → reads corrupted local (but readr may succeed with unexpected result)
  result_corrupted <- tryCatch(
    suppressMessages(gdpins_raw_get(conn, "data.csv")),
    error = function(e) NULL
  )

  # With force_refresh → re-downloads original from Drive
  result_refreshed <- suppressMessages(gdpins_raw_get(conn, "data.csv", force_refresh = TRUE))

  expect_equal(nrow(result_refreshed), nrow(original))
  expect_false(identical(result_corrupted, result_refreshed))
})

test_that("[LIVE] refresh_disconnect runs without error", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id    <- .live_test_root()
  local_path <- tempfile("gdpins_live_disc_")
  fs::dir_create(local_path)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("disc-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  conn <- gdpins_raw_connect(
    drive_path     = test_sub,
    local_path     = local_path,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  suppressMessages(gdpins_raw_put_file(conn, fx_csv_path(), "data.csv"))

  expect_no_error(suppressMessages(gdpins_refresh_disconnect(conn)))
  expect_true(file.exists(file.path(local_path, "data.csv")))
})

# ── Geospatial edge cases ─────────────────────────────────────────────────────

test_that("[LIVE] board round-trip: non-4326 sf (EPSG 3857) preserves CRS", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_3857_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("geo3857-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "geo3857",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  sf_obj <- fx_sf_non4326()
  suppressMessages(gdpins_pin_write(board, sf_obj, "web_mercator"))
  result <- gdpins_pin_read(board, "web_mercator")

  expect_s3_class(result, "sf")
  expect_equal(sf::st_crs(result)$epsg, 3857L)
  expect_equal(nrow(result), nrow(sf_obj))
})

test_that("[LIVE] board round-trip: multi-CRS sf preserves all geometry columns", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id   <- .live_test_root()
  cache_dir <- tempfile("gdpins_live_multicrs_")
  fs::dir_create(cache_dir)

  adapter  <- gdpins_real_drive(root_id)
  test_sub <- paste0("multicrs-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer(tryCatch(adapter$trash(test_sub), error = function(e) NULL))

  board <- gdpins_init_board(
    name           = "multicrs",
    drive_path     = test_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  sf_obj <- fx_sf_multi_crs()
  suppressMessages(gdpins_pin_write(board, sf_obj, "multi_geom"))
  result <- gdpins_pin_read(board, "multi_geom")

  expect_s3_class(result, "sf")
  expect_equal(nrow(result), nrow(sf_obj))
  # Both geometry columns survive
  geom_cols <- names(result)[vapply(result, inherits, logical(1L), "sfc")]
  expect_length(geom_cols, 2L)
  # CRS preserved for each
  expect_equal(sf::st_crs(result$geom_wgs)$epsg, 4326L)
  expect_equal(sf::st_crs(result$geom_web)$epsg, 3857L)
})

# ── Output publishing ─────────────────────────────────────────────────────────

test_that("[LIVE] gdpins_publish_output: tables + figures reach Drive", {
  .skip_live()
  gdpins_ensure_drive_auth()

  root_id     <- .live_test_root()
  cache_dir   <- tempfile("gdpins_live_pub_cache_")
  figures_dir <- tempfile("gdpins_live_pub_figs_")
  fs::dir_create(cache_dir)
  fs::dir_create(figures_dir)

  adapter      <- gdpins_real_drive(root_id)
  tables_sub   <- paste0("pub-tables-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  figures_sub  <- paste0("pub-figs-", format(Sys.time(), "%Y%m%dT%H%M%S"))
  withr::defer({
    tryCatch(adapter$trash(tables_sub),  error = function(e) NULL)
    tryCatch(adapter$trash(figures_sub), error = function(e) NULL)
  })

  # Build a local tables board with one pin
  tables_board <- gdpins_init_board(
    name           = "pub_tables",
    drive_path     = tables_sub,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )
  suppressMessages(gdpins_pin_write(tables_board, fx_output_table(), "summary"))

  # Save a figure to figures_dir
  gdpins_save_figure(fx_ggplot(), "test_plot", figures_dir)

  # Publish
  suppressMessages(gdpins_publish_output(
    tables_board  = tables_board,
    figures_dir   = figures_dir,
    drive_tables  = tables_sub,
    drive_figures = figures_sub,
    adapter       = adapter
  ))

  # Verify table was uploaded (as .rds under drive_tables)
  expect_true(gd_exists(adapter, paste0(tables_sub, "/summary.rds")))
  # Verify figure was uploaded
  expect_true(gd_exists(adapter, paste0(figures_sub, "/test_plot.png")))
})

# ── Auth ──────────────────────────────────────────────────────────────────────

test_that("[LIVE] auth: gdpins_ensure_drive_auth is idempotent", {
  .skip_live()
  gdpins_ensure_drive_auth()
  # Second call should be a no-op (token already set)
  expect_no_error(gdpins_ensure_drive_auth())
  expect_true(googledrive::drive_has_token())
})
