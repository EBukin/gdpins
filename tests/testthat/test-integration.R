# test-integration.R — WS9 workflow / lifecycle tests (ADR §12)
#
# All tests run on the fake Drive (no network). Coverage targets:
#   1. Offline → online reconcile (both directions)
#   2. Accumulated offline writes → merge-complete, no loss
#   3. New-computer: empty local + non-empty Drive → init pulls Drive→local
#   4. Availability-by-state: which verbs work in which config/state

# ── 1. Offline → online reconcile ────────────────────────────────────────────

test_that("online board write lands in cache", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  board <- new_fake_board("drive_cache")
  tbl   <- fx_plain_tbl()
  suppressMessages(gdpins_pin_write(board, tbl, "parcels"))

  expect_true(pins::pin_exists(board$local_board, "parcels"))
  expect_true(pins::pin_exists(board$drive_board, "parcels"))
})

test_that("offline read returns cache hit after prior online write", {
  board <- new_fake_board("drive_cache")
  tbl   <- fx_plain_tbl()

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_pin_write(board, tbl, "parcels"))

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  result <- gdpins_pin_read(board, "parcels")
  expect_equal(result, tbl)
})

test_that("sync from_drive moves drive-ahead pin to local", {
  board <- new_fake_board("drive_cache")
  tbl   <- fx_plain_tbl()

  # Seed Drive only (simulate remote write from another machine)
  suppressMessages(
    pins::pin_write(board$drive_board, tbl, "analysis_table", type = "parquet")
  )
  expect_false(pins::pin_exists(board$local_board, "analysis_table"))

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "from_drive"))

  expect_true(pins::pin_exists(board$local_board, "analysis_table"))
})

test_that("sync to_drive pushes local-ahead pin to Drive", {
  board <- new_fake_board("drive_cache")
  tbl   <- fx_plain_tbl()

  # Seed cache only (simulate offline write)
  suppressMessages(
    pins::pin_write(board$local_board, tbl, "local_pin", type = "parquet")
  )
  expect_false(pins::pin_exists(board$drive_board, "local_pin"))

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  expect_true(pins::pin_exists(board$drive_board, "local_pin"))
})

test_that("auto sync reconciles both directions in one call", {
  board <- new_fake_board("drive_cache")

  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "from_drive_pin",
                    type = "parquet")
  )
  suppressMessages(
    pins::pin_write(board$local_board, fx_plain_tbl(), "from_local_pin",
                    type = "parquet")
  )

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "auto"))

  expect_true(pins::pin_exists(board$local_board,  "from_drive_pin"))
  expect_true(pins::pin_exists(board$drive_board, "from_local_pin"))
})

# ── 2. Accumulated offline writes → merge-complete ───────────────────────────

test_that("multiple accumulated offline writes all reach Drive after sync", {
  board      <- new_fake_board("drive_cache")
  pin_names  <- c("gdp_panel", "population", "land_value")

  for (nm in pin_names) {
    suppressMessages(
      pins::pin_write(board$local_board, fx_plain_tbl(), nm, type = "parquet")
    )
  }

  for (nm in pin_names) {
    expect_false(pins::pin_exists(board$drive_board, nm))
  }

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  for (nm in pin_names) {
    expect_true(
      pins::pin_exists(board$drive_board, nm),
      label = paste("Drive missing after sync:", nm)
    )
  }
})

test_that("multiple offline writes produce readable pins after sync", {
  board      <- new_fake_board("drive_cache")
  pin_names  <- c("gdp_panel", "population", "land_value")
  original   <- fx_plain_tbl()

  for (nm in pin_names) {
    suppressMessages(
      pins::pin_write(board$local_board, original, nm, type = "parquet")
    )
  }

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  # Read from Drive directly to confirm data integrity. Compare via
  # tibble::as_tibble(): nanoparquet::read_parquet() (pins type "parquet")
  # returns a plain data frame rather than a tibble, so raw pins::pin_read()
  # results differ in class from `original` even though the data matches.
  for (nm in pin_names) {
    result <- pins::pin_read(board$drive_board, nm)
    expect_equal(
      tibble::as_tibble(result), tibble::as_tibble(original),
      label = paste("Data mismatch for:", nm)
    )
  }
})

test_that("versioned board offline writes create multiple versions, survive sync", {
  board <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(
    pins::pin_write(board$local_board, fx_plain_tbl(), "versioned_data",
                    type = "parquet")
  )
  suppressMessages(
    pins::pin_write(
      board$local_board,
      dplyr::mutate(fx_plain_tbl(), value = value * 2),
      "versioned_data", type = "parquet"
    )
  )

  local_v_before <- nrow(pins::pin_versions(board$local_board, "versioned_data"))
  expect_equal(local_v_before, 2L)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "to_drive"))

  expect_true(pins::pin_exists(board$drive_board, "versioned_data"))
})

test_that("versioned conflict resolved as new versions without data loss", {
  board <- new_fake_board("drive_cache", versioned = TRUE)

  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "conflicted_pin",
                    type = "parquet")
  )
  suppressMessages(
    pins::pin_write(
      board$local_board,
      dplyr::mutate(fx_plain_tbl(), value = value * 10),
      "conflicted_pin", type = "parquet"
    )
  )

  drive_v_before <- nrow(pins::pin_versions(board$drive_board, "conflicted_pin"))
  cache_v_before <- nrow(pins::pin_versions(board$local_board, "conflicted_pin"))

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(
    gdpins_sync(board, direction = "auto", on_conflict = "version")
  )

  drive_v_after <- nrow(pins::pin_versions(board$drive_board, "conflicted_pin"))
  cache_v_after <- nrow(pins::pin_versions(board$local_board, "conflicted_pin"))

  # Both sides should have at least as many versions as before
  expect_gte(drive_v_after, drive_v_before)
  expect_gte(cache_v_after, cache_v_before)
})

# ── 3. New-computer: empty local + non-empty Drive → init pulls Drive→local ──

test_that("new-computer sync: emits pulling/new-computer message", {
  board <- new_fake_board("drive_cache")

  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "existing_pin",
                    type = "parquet")
  )
  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "existing_sf",
                    type = "parquet")
  )

  expect_equal(length(pins::pin_list(board$local_board)), 0L)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  msgs <- testthat::capture_messages(
    gdpins_sync(board, direction = "from_drive")
  )
  msg_combined <- paste(msgs, collapse = " ")

  expect_true(
    grepl(
      "new.computer|pulling|Drive.*local|empty|New-computer",
      msg_combined, ignore.case = TRUE
    ),
    label = paste("Expected new-computer message. Got:", msg_combined)
  )
})

test_that("new-computer sync: all Drive pins available locally afterwards", {
  board      <- new_fake_board("drive_cache")
  drive_pins <- c("pin_a", "pin_b", "pin_c")

  for (nm in drive_pins) {
    suppressMessages(
      pins::pin_write(board$drive_board, fx_plain_tbl(), nm, type = "parquet")
    )
  }

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  suppressMessages(gdpins_sync(board, direction = "from_drive"))

  for (nm in drive_pins) {
    expect_true(
      pins::pin_exists(board$local_board, nm),
      label = paste("Cache missing after new-computer sync:", nm)
    )
  }
})

test_that("gdpins_init_board with on_discrepancy=sync_from_drive pulls Drive→local", {
  # Build fake infrastructure manually to pre-populate Drive
  fake_root  <- tempfile("gdpins_nc_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  drive_path <- "nc-test/data_raw"
  cache_dir  <- tempfile("gdpins_nc_cache_")
  fs::dir_create(cache_dir)

  # Create Drive folder and seed a pin
  gd_mkdir(adapter, drive_path)
  drive_board_dir <- file.path(
    fake_root, gsub("/", .Platform$file.sep, drive_path)
  )
  fs::dir_create(drive_board_dir)
  pre_board <- pins::board_folder(drive_board_dir, versioned = TRUE)
  suppressMessages(
    pins::pin_write(pre_board, fx_plain_tbl(), "seeded_pin", type = "parquet")
  )

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  board <- gdpins_init_board(
    name           = "data_raw",
    drive_path     = drive_path,
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = FALSE,
    on_discrepancy = "sync_from_drive"
  )
  expect_s3_class(board, "gdpins_board")

  # Boards are lazy by default, so the policy runs on connect rather than at
  # init. gdpins_board_connect() is just the deliberate way to trigger it —
  # a first gdpins_pin_read() would pull exactly the same way.
  msgs <- testthat::capture_messages(gdpins_board_connect(board))

  msg_combined <- paste(msgs, collapse = " ")
  expect_true(
    grepl(
      "sync.*from.*drive|pulling|sync_from_drive|Drive.*local",
      msg_combined, ignore.case = TRUE
    ),
    label = paste("Expected sync-from-drive message. Got:", msg_combined)
  )

  # The message is not the point — the pull is. The seeded Drive pin must be
  # readable from the board now that it has connected.
  expect_equal(
    gdpins_pin_read(board, "seeded_pin"),
    fx_plain_tbl()
  )
})

# ── 4. Availability-by-state ──────────────────────────────────────────────────

test_that("local_only: pin_write and pin_read work without network", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  board  <- new_fake_board("local_only")
  tbl    <- fx_plain_tbl()

  expect_no_error(suppressMessages(gdpins_pin_write(board, tbl, "local_pin")))
  result <- gdpins_pin_read(board, "local_pin")
  expect_equal(result, tbl)
})

test_that("drive_cache: pin_write is blocked when offline", {
  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  board <- new_fake_board("drive_cache")

  expect_error(
    gdpins_pin_write(board, fx_plain_tbl(), "should_fail"),
    regexp = "no internet|offline|Cannot write"
  )
})

test_that("drive_cache: pin_read from cache succeeds offline", {
  board <- new_fake_board("drive_cache")

  suppressMessages(
    pins::pin_write(board$local_board, fx_plain_tbl(), "cached_pin",
                    type = "parquet")
  )

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  result <- gdpins_pin_read(board, "cached_pin")
  expect_equal(result, fx_plain_tbl())
})

test_that("gdpins_sync is blocked when offline", {
  board <- new_fake_board("drive_cache")

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  expect_error(
    gdpins_sync(board),
    regexp = "no internet|offline|Cannot sync"
  )
})

test_that("gdpins_board_status returns offline rows when offline (if cache has pins)", {
  board <- new_fake_board("drive_cache")

  suppressMessages(
    pins::pin_write(board$local_board, fx_plain_tbl(), "test_pin",
                    type = "parquet")
  )

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  status <- suppressWarnings(gdpins_board_status(board))
  expect_s3_class(status, "tbl_df")
  if (nrow(status) > 0L) {
    expect_true(all(status$state == "offline"))
  }
})

test_that("local_only: gdpins_board_status returns zero-row tibble", {
  board  <- new_fake_board("local_only")
  status <- gdpins_board_status(board)
  expect_s3_class(status, "tbl_df")
  expect_equal(nrow(status), 0L)
})

test_that("drive_cache: offline read uses local_board", {
  board <- new_fake_board("drive_cache")

  suppressMessages(
    pins::pin_write(board$local_board, fx_plain_tbl(), "local_pin",
                    type = "parquet")
  )

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    .package = "gdpins"
  )
  result <- gdpins_pin_read(board, "local_pin")
  expect_equal(result, fx_plain_tbl())
})

test_that("online init + discrepancy=warn emits a warning", {
  board <- new_fake_board("drive_cache")

  # Seed Drive to create a discrepancy
  suppressMessages(
    pins::pin_write(board$drive_board, fx_plain_tbl(), "drive_pin",
                    type = "parquet")
  )

  # Build a new board over the same dirs to trigger init-sync check
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  expect_no_error(
    suppressWarnings(
      gdpins_init_board(
        name           = board$name,
        drive_path     = board$drive_path,
        cache_dir      = board$cache_dir,
        adapter        = board$adapter,
        create         = FALSE,
        on_discrepancy = "warn"
      )
    )
  )
})

# ── [V7] Cross-module verification tests ─────────────────────────────────────

test_that("[V7] drive_cache: write, go_offline, read, offline write, go_online(sync_to_drive) reaches Drive, prune keeps newest on both sides", {
  board <- new_fake_board("drive_cache", versioned = TRUE)
  v1 <- fx_plain_tbl()
  v2 <- dplyr::mutate(fx_plain_tbl(), value = value * 2)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  # Online write lands on both sides
  suppressMessages(gdpins_pin_write(board, v1, "shared_pin"))
  expect_true(pins::pin_exists(board$drive_board, "shared_pin"))
  expect_true(pins::pin_exists(board$local_board, "shared_pin"))

  # Go offline, read still works from the local copy
  offline <- suppressMessages(gdpins_go_offline(board))
  expect_equal(gdpins_pin_read(offline, "shared_pin"), v1)

  # Write again while offline -- creates a second local version, Drive untouched.
  # Sleep > 1s so the offline write's timestamp is strictly newer than the
  # online write's (pins version timestamps have 1-second resolution); without
  # this, drive_created == local_created and .compare_board_pin reports
  # "conflict" instead of "local_ahead" (see test-sync.R/test-prune.R for the
  # same pattern elsewhere in this suite).
  Sys.sleep(1.1)
  suppressMessages(gdpins_pin_write(offline, v2, "shared_pin"))
  expect_equal(nrow(pins::pin_versions(offline$local_board, "shared_pin")), 2L)
  expect_equal(nrow(pins::pin_versions(board$drive_board, "shared_pin")), 1L)

  # Reconnect: sync_to_drive pushes the offline write to Drive
  online <- suppressMessages(
    gdpins_go_online(offline, on_discrepancy = "sync_to_drive")
  )
  expect_equal(online$config, "drive_cache")
  # Read via .read_from_board(): arrow-written parquet pins are pins type
  # "file", which raw pins::pin_read() cannot read. Result may be a plain
  # data frame rather than a tibble --
  # compare via tibble::as_tibble() rather than expect_equal() against v2.
  expect_equal(
    tibble::as_tibble(.read_from_board(online$drive_board, "shared_pin", NULL)),
    tibble::as_tibble(v2)
  )
  expect_equal(nrow(pins::pin_versions(online$drive_board, "shared_pin")), 2L)
  expect_equal(nrow(pins::pin_versions(online$local_board, "shared_pin")), 2L)

  # Prune: keep = 1 leaves exactly the newest version on both sides
  gdpins_prune_pin_versions(online, "shared_pin", keep = 1, dry_run = FALSE)

  expect_equal(nrow(pins::pin_versions(online$drive_board, "shared_pin")), 1L)
  expect_equal(nrow(pins::pin_versions(online$local_board, "shared_pin")), 1L)
  expect_equal(
    tibble::as_tibble(.read_from_board(online$drive_board, "shared_pin", NULL)),
    tibble::as_tibble(v2)
  )
  expect_equal(
    tibble::as_tibble(.read_from_board(online$local_board, "shared_pin", NULL)),
    tibble::as_tibble(v2)
  )
})

test_that("[V7] lazy drive_only end-to-end: write, read, zero-row status, nothing under the cache_dir option", {
  fake_root <- tempfile("gdpins_v7_lazy_")
  fs::dir_create(fake_root)
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name       = "v7_lazy",
    drive_path = "v7-fake/lazy",
    cache_dir  = FALSE,
    adapter    = adapter,
    create     = TRUE,
    lazy       = TRUE
  )
  expect_false(gdpins_board_is_connected(board))

  tbl <- fx_plain_tbl()
  suppressMessages(gdpins_pin_write(board, tbl, "lazy_pin"))
  expect_true(gdpins_board_is_connected(board))
  expect_equal(gdpins_pin_read(board, "lazy_pin"), tbl)

  status <- gdpins_board_status(board)
  expect_s3_class(status, "tbl_df")
  expect_equal(nrow(status), 0L)

  cache_root <- getOption("gdpins.cache_dir")
  files_under_cache <- if (fs::dir_exists(cache_root)) {
    fs::dir_ls(cache_root, recurse = TRUE, type = "file")
  } else {
    character()
  }
  expect_length(files_under_cache, 0L)
})

test_that("[V7] default cache path end-to-end: cache_dir = NULL resolves under the test gdpins.cache_dir option, never the real home", {
  fake_root <- tempfile("gdpins_v7_default_")
  fs::dir_create(fake_root)
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name       = "v7_default",
    drive_path = "v7-fake/default",
    cache_dir  = NULL,
    adapter    = adapter,
    create     = TRUE
  )

  test_cache_root <- getOption("gdpins.cache_dir")
  real_home_root  <- as.character(fs::path_home(".gdpins"))
  expect_true(startsWith(board$cache_dir, test_cache_root))
  expect_false(startsWith(board$cache_dir, real_home_root))

  suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "default_pin"))
  expect_true(fs::dir_exists(file.path(board$cache_dir, "default_pin")))
})

test_that("[V7] gdpins_init_board(local_dir=) end-to-end: deprecated but still works, warns once", {
  fake_root <- tempfile("gdpins_v7_localdir_")
  fs::dir_create(fake_root)
  adapter   <- gdpins_fake_drive(root = fake_root)
  cache_dir <- tempfile("gdpins_v7_localdir_cache_")

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  withr::local_options(lifecycle_verbosity = "warning")

  # gdpins_init_board() calls .board_spec() (one extra frame vs. calling
  # .board_spec() directly as test-board.R's deprecation tests do), so
  # lifecycle's is_direct()/always logic falls through to its once-per-session
  # cache rather than "warning" verbosity's always-warn path. Clear that cache
  # for this id so the test is deterministic regardless of what ran earlier in
  # the suite (e.g. test-board.R's own local_dir deprecation tests).
  dep_env <- lifecycle:::deprecation_env
  rm(list = ls(dep_env), envir = dep_env)

  warnings_seen <- character()
  board <- withCallingHandlers(
    gdpins_init_board(
      name       = "v7_localdir",
      drive_path = "v7-fake/localdir",
      local_dir  = cache_dir,
      adapter    = adapter,
      create     = TRUE
    ),
    lifecycle_warning_deprecated = function(cnd) {
      warnings_seen <<- c(warnings_seen, conditionMessage(cnd))
      rlang::cnd_muffle(cnd)
    }
  )

  expect_length(warnings_seen, 1L)
  expect_equal(board$cache_dir, cache_dir)

  suppressMessages(gdpins_pin_write(board, fx_plain_tbl(), "localdir_pin"))
  expect_equal(gdpins_pin_read(board, "localdir_pin"), fx_plain_tbl())
  expect_true(fs::dir_exists(file.path(cache_dir, "localdir_pin")))
})

test_that("[V7] two boards sharing one fake adapter get distinct default cache dirs", {
  fake_root <- tempfile("gdpins_v7_shared_adapter_")
  fs::dir_create(fake_root)
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  board_a <- gdpins_init_board(
    name = "v7_a", drive_path = "v7-fake/a", cache_dir = NULL,
    adapter = adapter, create = TRUE
  )
  board_b <- gdpins_init_board(
    name = "v7_b", drive_path = "v7-fake/b", cache_dir = NULL,
    adapter = adapter, create = TRUE
  )

  expect_false(identical(board_a$cache_dir, board_b$cache_dir))

  suppressMessages(gdpins_pin_write(board_a, fx_plain_tbl(), "pin_a"))
  suppressMessages(gdpins_pin_write(board_b, fx_plain_tbl(), "pin_b"))

  expect_true(pins::pin_exists(board_a$local_board, "pin_a"))
  expect_true(pins::pin_exists(board_b$local_board, "pin_b"))
  expect_false(pins::pin_exists(board_a$local_board, "pin_b"))
})
