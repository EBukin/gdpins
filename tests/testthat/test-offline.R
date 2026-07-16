# test-offline.R — gdpins_go_offline() / gdpins_go_online() tests
# Uses new_fake_board()/new_fake_raw_conn() harnesses (no network) for the
# bulk of coverage; one gated test exercises a real Drive folder.

# mock_status_*() fixtures live in helper-fakes.R.

# ── Generic dispatch ──────────────────────────────────────────────────────────

test_that("gdpins_go_offline() errors on unsupported class", {
  expect_error(gdpins_go_offline(list()), "gdpins_board.*gdpins_raw_conn")
})

test_that("gdpins_go_online() errors on unsupported class", {
  expect_error(gdpins_go_online(list()), "gdpins_board.*gdpins_raw_conn")
})

# ── gdpins_go_offline.gdpins_board ────────────────────────────────────────────

test_that("gdpins_go_offline() on a local_only board is a no-op", {
  board <- new_fake_board(config = "local_only")
  expect_message(offline <- gdpins_go_offline(board), "already local-only")
  expect_identical(offline, board)
})

test_that("gdpins_go_offline() converts drive_cache board to local_only using cache dir", {
  board <- new_fake_board(config = "drive_cache")
  expect_message(offline <- gdpins_go_offline(board), "local-only")
  expect_s3_class(offline, "gdpins_board")
  expect_equal(offline$config, "local_only")
  expect_null(offline$drive_board)
  expect_null(offline$cache_board)
  expect_null(offline$adapter)
  expect_identical(offline$local_board, board$cache_board)
  expect_equal(offline$local_dir, board$cache_dir)
  expect_equal(offline$name, board$name)
})

test_that("gdpins_go_offline() converts drive_cache_local board to local_only using local_dir", {
  board <- new_fake_board(config = "drive_cache_local")
  offline <- suppressMessages(gdpins_go_offline(board))
  expect_equal(offline$config, "local_only")
  expect_identical(offline$local_board, board$local_board)
  expect_equal(offline$local_dir, board$local_dir)
})

test_that("gdpins_go_offline() preserves reads/writes locally while offline", {
  board   <- new_fake_board(config = "drive_cache_local")
  offline <- suppressMessages(gdpins_go_offline(board))

  gdpins_pin_write(offline, mtcars, "cars", format = "rds")
  expect_equal(gdpins_pin_read(offline, "cars"), mtcars)

  # Write landed on the same local_board object -- visible via the original too
  expect_true(pins::pin_exists(board$local_board, "cars"))
  # ...but never reached Drive or the cache
  expect_false(pins::pin_exists(board$drive_board, "cars"))
  expect_false(pins::pin_exists(board$cache_board, "cars"))
})

test_that("gdpins_go_offline() stashes the original Drive configuration", {
  board   <- new_fake_board(config = "drive_cache")
  offline <- suppressMessages(gdpins_go_offline(board))
  state   <- attr(offline, "gdpins_offline_state")
  expect_equal(state$config, "drive_cache")
  expect_identical(state$adapter, board$adapter)
  expect_equal(state$drive_path, board$drive_path)
})

# ── gdpins_go_online.gdpins_board ─────────────────────────────────────────────

test_that("gdpins_go_online() errors if the board never went offline via gdpins_go_offline()", {
  board <- new_fake_board(config = "local_only")
  expect_error(gdpins_go_online(board), "no stored Drive configuration")
})

test_that("gdpins_go_online() errors when there is no internet connection", {
  board   <- new_fake_board(config = "drive_cache")
  offline <- suppressMessages(gdpins_go_offline(board))
  testthat::local_mocked_bindings(gdpins_is_online = function() FALSE, .package = "gdpins")
  expect_error(gdpins_go_online(offline), "no internet connection")
})

test_that("gdpins_go_online() restores a drive_cache board and reattaches the adapter", {
  board   <- new_fake_board(config = "drive_cache")
  offline <- suppressMessages(gdpins_go_offline(board))

  testthat::local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  online <- suppressMessages(gdpins_go_online(offline, on_discrepancy = "ignore"))
  expect_equal(online$config, "drive_cache")
  expect_identical(online$adapter, board$adapter)
  expect_identical(online$drive_board, board$drive_board)
  expect_identical(online$cache_board, board$cache_board)
  expect_equal(online$drive_path, board$drive_path)
  expect_null(online$local_board)
})

test_that("gdpins_go_online() restores a drive_cache_local board, keeping local_board", {
  board   <- new_fake_board(config = "drive_cache_local")
  offline <- suppressMessages(gdpins_go_offline(board))

  testthat::local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  online <- suppressMessages(gdpins_go_online(offline, on_discrepancy = "ignore"))
  expect_equal(online$config, "drive_cache_local")
  expect_identical(online$local_board, board$local_board)
  expect_identical(online$drive_board, board$drive_board)
  expect_equal(online$local_dir, board$local_dir)
})

test_that("gdpins_go_online() accepts an override adapter", {
  board       <- new_fake_board(config = "drive_cache")
  offline     <- suppressMessages(gdpins_go_offline(board))
  new_adapter <- gdpins_fake_drive()

  testthat::local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  online <- suppressMessages(
    gdpins_go_online(offline, adapter = new_adapter, on_discrepancy = "ignore")
  )
  expect_identical(online$adapter, new_adapter)
})

test_that("gdpins_go_online() runs a sync when on_discrepancy = sync_to_drive", {
  board   <- new_fake_board(config = "drive_cache_local")
  offline <- suppressMessages(gdpins_go_offline(board))
  gdpins_pin_write(offline, mtcars, "cars") # written while offline

  sync_called <- FALSE
  testthat::local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) mock_status_row(
      name = "cars", state = "local_ahead", local_version = "20260102T120000Z-bbb"
    ),
    gdpins_sync = function(x, direction, ...) {
      sync_called <<- TRUE
      invisible(x)
    },
    .package = "gdpins"
  )

  suppressMessages(gdpins_go_online(offline, on_discrepancy = "sync_to_drive"))
  expect_true(sync_called)
})

# ── Round trip: fake adapter, real data flow (no status/sync mocking) ────────

test_that("go_offline -> write -> go_online(sync_to_drive) pushes the pin to Drive (fake)", {
  board   <- new_fake_board(config = "drive_cache_local")
  offline <- suppressMessages(gdpins_go_offline(board))
  gdpins_pin_write(offline, mtcars, "cars", format = "rds")

  online <- suppressMessages(
    gdpins_go_online(offline, on_discrepancy = "sync_to_drive")
  )

  expect_true(pins::pin_exists(board$drive_board, "cars"))
  expect_true(pins::pin_exists(board$cache_board, "cars"))
  expect_equal(gdpins_pin_read(online, "cars"), mtcars)
})

test_that("go_offline -> write -> go_online(drive_cache) pushes the pin to Drive (fake)", {
  board   <- new_fake_board(config = "drive_cache")
  offline <- suppressMessages(gdpins_go_offline(board))
  gdpins_pin_write(offline, mtcars, "cars", format = "rds")

  online <- suppressMessages(
    gdpins_go_online(offline, on_discrepancy = "sync_to_drive")
  )

  expect_true(pins::pin_exists(board$drive_board, "cars"))
  expect_equal(gdpins_pin_read(online, "cars"), mtcars)
})

# ── gdpins_go_offline.gdpins_raw_conn ──────────────────────────────────────────

test_that("gdpins_go_offline() on a local_only raw_conn is a no-op", {
  conn <- new_fake_raw_conn(config = "local_only")
  expect_message(offline <- gdpins_go_offline(conn), "already local-only")
  expect_identical(offline, conn)
})

test_that("gdpins_go_offline() converts drive_local raw_conn to local_only", {
  conn    <- new_fake_raw_conn(config = "drive_local")
  offline <- suppressMessages(gdpins_go_offline(conn))
  expect_s3_class(offline, "gdpins_raw_conn")
  expect_equal(offline$config, "local_only")
  expect_null(offline$adapter)
  expect_null(offline$drive_path)
  expect_equal(offline$local_path, conn$local_path)
})

test_that("gdpins_go_offline() raw_conn: local reads/writes work while offline", {
  conn    <- new_fake_raw_conn(config = "drive_local")
  offline <- suppressMessages(gdpins_go_offline(conn))

  gdpins_raw_put_object(offline, mtcars, "cars.rds")
  expect_equal(gdpins_raw_get(offline, "cars.rds"), mtcars)
  expect_false(gd_exists(conn$adapter, paste0(conn$drive_path, "/cars.rds")))
})

test_that("gdpins_go_offline() stashes raw_conn Drive configuration", {
  conn    <- new_fake_raw_conn(config = "drive_local")
  offline <- suppressMessages(gdpins_go_offline(conn))
  state   <- attr(offline, "gdpins_offline_state")
  expect_equal(state$config, "drive_local")
  expect_identical(state$adapter, conn$adapter)
  expect_equal(state$drive_path, conn$drive_path)
})

# ── gdpins_go_online.gdpins_raw_conn ──────────────────────────────────────────

test_that("gdpins_go_online() raw_conn errors without prior gdpins_go_offline()", {
  conn <- new_fake_raw_conn(config = "local_only")
  expect_error(gdpins_go_online(conn), "no stored Drive configuration")
})

test_that("gdpins_go_online() restores a drive_local raw_conn", {
  conn    <- new_fake_raw_conn(config = "drive_local")
  offline <- suppressMessages(gdpins_go_offline(conn))

  testthat::local_mocked_bindings(
    gdpins_is_online    = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  online <- suppressMessages(gdpins_go_online(offline, on_discrepancy = "ignore"))
  expect_equal(online$config, "drive_local")
  expect_identical(online$adapter, conn$adapter)
  expect_equal(online$drive_path, conn$drive_path)
  expect_equal(online$local_path, conn$local_path)
})

test_that("go_offline -> put_object -> go_online(sync_to_drive) pushes file to Drive (fake)", {
  conn    <- new_fake_raw_conn(config = "drive_local")
  offline <- suppressMessages(gdpins_go_offline(conn))
  gdpins_raw_put_object(offline, mtcars, "cars.rds")

  online <- suppressMessages(
    gdpins_go_online(offline, on_discrepancy = "sync_to_drive")
  )

  expect_true(gd_exists(online$adapter, paste0(online$drive_path, "/cars.rds")))
})

# ── Real Drive round trip (skip unless live) ─────────────────────────────────

test_that("gdpins_go_offline()/gdpins_go_online() round trip against a real Drive folder", {
  skip_on_ci()
  skip_if(
    nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")),
    "Skipping live Drive auth during R CMD check"
  )
  skip_if_offline()
  folder_id <- Sys.getenv("GDRIVE_TEST_FOLDER")
  skip_if(!nzchar(folder_id), "GDRIVE_TEST_FOLDER not set")

  gdpins_ensure_drive_auth()
  adapter <- gdpins_real_drive(folder_id)

  cache_dir <- withr::local_tempdir()
  board <- gdpins_init_board(
    name           = "gdpins_offline_test",
    drive_path     = "gdpins-offline-test",
    cache_dir      = cache_dir,
    adapter        = adapter,
    create         = TRUE,
    on_discrepancy = "ignore"
  )

  offline <- suppressMessages(gdpins_go_offline(board))
  expect_equal(offline$config, "local_only")

  gdpins_pin_write(offline, mtcars, "cars_offline_test", format = "rds")
  expect_equal(gdpins_pin_read(offline, "cars_offline_test"), mtcars)

  online <- suppressMessages(
    gdpins_go_online(offline, on_discrepancy = "sync_to_drive")
  )
  expect_equal(online$config, "drive_cache")
  expect_true(pins::pin_exists(online$drive_board, "cars_offline_test"))

  # Cleanup: remove the test pin from Drive
  gdpins_pin_remove(online, "cars_offline_test")
})
