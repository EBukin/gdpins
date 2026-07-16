# test-board.R — WS3 tests for gdpins_init_board + S3 methods
# Uses new_fake_board() harness (no network).

# This file tests what init *builds* — components, the create/offline branches,
# and the on_discrepancy sync check — so it pins boards to the eager path.
# Under the lazy default that work is deferred to first use and none of these
# assertions would fire at the init call. The deferral itself, and the fact
# that this same work still happens on connect, is test-lazy.R's job.
withr::local_options(gdpins.lazy_boards = FALSE)

# ── 1. Config: local_only ─────────────────────────────────────────────────────

test_that("local_only board builds with correct components", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- gdpins_init_board(
    name = "myboard",
    local_dir = local_dir,
    on_discrepancy = "ignore"
  )
  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "local_only")
  expect_equal(board$name, "myboard")
  expect_true(!is.null(board$local_board))
  expect_null(board$drive_board)
  expect_null(board$cache_board)
  expect_null(board$adapter)
  expect_equal(board$local_dir, local_dir)
  expect_true(board$versioned)
})

test_that("local_only board creates local_dir if missing", {
  parent_dir <- withr::local_tempdir()
  local_dir <- file.path(parent_dir, "new_subdir")
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- gdpins_init_board(
    name = "x",
    local_dir = local_dir,
    on_discrepancy = "ignore"
  )
  expect_true(dir.exists(local_dir))
  expect_equal(board$config, "local_only")
})

test_that("local_only board respects versioned = FALSE", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- gdpins_init_board(
    name = "unversioned",
    local_dir = local_dir,
    versioned = FALSE,
    on_discrepancy = "ignore"
  )
  expect_false(board$versioned)
})

# ── 2. Config: drive_cache ────────────────────────────────────────────────────

test_that("drive_cache board builds with correct components (fake adapter)", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "boards/myboard"

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "myboard",
    drive_path = drive_path,
    cache_dir = cache_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )

  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "drive_cache")
  expect_equal(board$name, "myboard")
  expect_true(!is.null(board$drive_board))
  expect_true(!is.null(board$cache_board))
  expect_null(board$local_board)
  expect_equal(board$drive_path, drive_path)
  expect_equal(board$cache_dir, cache_dir)
  expect_null(board$local_dir)
})

test_that("drive_cache board drive_board uses board_folder over fake root", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "boards/test"

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "test",
    drive_path = drive_path,
    cache_dir = cache_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )

  # The drive_board should be a board_folder rooted under the fake root
  expected_dir <- file.path(fake_root, "boards", "test")
  expect_true(dir.exists(expected_dir))
})

# ── 3. Config: drive_cache_local ──────────────────────────────────────────────

test_that("drive_cache_local board builds with all three components", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  local_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "boards/superboard"

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "superboard",
    drive_path = drive_path,
    cache_dir = cache_dir,
    local_dir = local_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )

  expect_equal(board$config, "drive_cache_local")
  expect_true(!is.null(board$drive_board))
  expect_true(!is.null(board$cache_board))
  expect_true(!is.null(board$local_board))
  expect_equal(board$local_dir, local_dir)
  expect_equal(board$cache_dir, cache_dir)
  expect_equal(board$drive_path, drive_path)
})

# ── 4. create-confirm logic ───────────────────────────────────────────────────

test_that("non-existent Drive path + create=FALSE -> error", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  expect_error(
    gdpins_init_board(
      name = "x",
      drive_path = "nonexistent/path",
      cache_dir = cache_dir,
      adapter = adapter,
      create = FALSE
    ),
    "Drive board path does not exist"
  )
})

test_that("non-existent Drive path + create=TRUE -> creates and builds board", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "newboard",
    drive_path = "new/path",
    cache_dir = cache_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )

  expect_s3_class(board, "gdpins_board")
  # Path was created on the fake drive
  expect_true(gd_exists(adapter, "new/path"))
})

test_that("non-existent Drive path + create=NA + non-interactive -> error", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  # Non-interactive (test env): create=NA should error
  expect_error(
    gdpins_init_board(
      name = "x",
      drive_path = "nonexistent/path2",
      cache_dir = cache_dir,
      adapter = adapter,
      create = NA
    ),
    "Non-interactive session"
  )
})

test_that("gdpins_init_board: fake adapter ignores .is_drive_id heuristic (path works)", {
  adapter <- gdpins_fake_drive()
  cache_dir <- withr::local_tempdir()

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "test",
    drive_path = "nodash",
    cache_dir = cache_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )

  expect_s3_class(board, "gdpins_board")
  expect_equal(board$drive_path, "nodash")
})

# ── 5. Offline fallback ───────────────────────────────────────────────────────

test_that("drive_cache offline -> falls back to local-only (cache dir), warns", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  expect_warning(
    board <- gdpins_init_board(
      name = "offline_board",
      drive_path = "some/path",
      cache_dir = cache_dir,
      adapter = adapter,
      on_discrepancy = "ignore"
    ),
    "No internet connection"
  )

  expect_equal(board$config, "local_only")
  expect_null(board$drive_board)
})

test_that("drive_cache_local offline -> falls back to local_dir-based board, warns", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  local_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  expect_warning(
    board <- gdpins_init_board(
      name = "super_offline",
      drive_path = "x/y",
      cache_dir = cache_dir,
      local_dir = local_dir,
      adapter = adapter,
      on_discrepancy = "ignore"
    ),
    "No internet connection"
  )

  expect_equal(board$config, "local_only")
  expect_equal(board$local_dir, local_dir)
})

# ── 6. on_discrepancy branches ────────────────────────────────────────────────

test_that("on_discrepancy=ignore: no message on discrepancy", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  # Should not warn or message
  expect_no_warning(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "ignore"
    )
  )
})

test_that("on_discrepancy=warn: emits a warning on discrepancy", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  expect_warning(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "warn"
    ),
    "sync discrepancy"
  )
})

test_that("on_discrepancy=sync_from_drive: attempts gdpins_sync from_drive", {
  local_dir <- withr::local_tempdir()
  sync_called <- FALSE
  sync_dir <- NULL

  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    gdpins_sync = function(board, direction, ...) {
      sync_called <<- TRUE
      sync_dir <<- direction
      invisible(board)
    },
    .package = "gdpins"
  )

  suppressMessages(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "sync_from_drive"
    )
  )

  expect_true(sync_called)
  expect_equal(sync_dir, "from_drive")
})

test_that("on_discrepancy=sync_to_drive: attempts gdpins_sync to_drive", {
  local_dir <- withr::local_tempdir()
  sync_called <- FALSE

  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    gdpins_sync = function(board, direction, ...) {
      sync_called <<- TRUE
      invisible(board)
    },
    .package = "gdpins"
  )

  suppressMessages(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "sync_to_drive"
    )
  )

  expect_true(sync_called)
})

test_that("on_discrepancy default = warn when non-interactive", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  # Non-interactive (test) + NULL discrepancy -> warn
  expect_warning(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = NULL
    ),
    "sync discrepancy"
  )
})

test_that("gdpins_board_status error during init is caught and warned", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) stop("WS5 not implemented"),
    .package = "gdpins"
  )
  # Should warn but not error
  expect_warning(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "warn"
    ),
    "gdpins_board_status"
  )
})

# ── 7. new_fake_board harness integration ─────────────────────────────────────

test_that("new_fake_board drive_cache has correct components", {
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- new_fake_board(config = "drive_cache")
  expect_s3_class(board, "gdpins_board")
  expect_equal(board$config, "drive_cache")
  expect_false(is.null(board$drive_board))
  expect_false(is.null(board$cache_board))
  expect_null(board$local_board)
})

test_that("new_fake_board local_only has correct components", {
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- new_fake_board(config = "local_only")
  expect_equal(board$config, "local_only")
  expect_false(is.null(board$local_board))
  expect_null(board$drive_board)
  expect_null(board$cache_board)
})

test_that("new_fake_board drive_cache_local has all three components", {
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  board <- new_fake_board(config = "drive_cache_local")
  expect_equal(board$config, "drive_cache_local")
  expect_false(is.null(board$drive_board))
  expect_false(is.null(board$cache_board))
  expect_false(is.null(board$local_board))
})

# ── 8. Validation errors ──────────────────────────────────────────────────────

test_that("empty name errors", {
  expect_error(
    gdpins_init_board(name = "", local_dir = withr::local_tempdir()),
    "non-empty character scalar"
  )
})

test_that("no drive_path and no local_dir -> error", {
  expect_error(
    gdpins_init_board(name = "x"),
    "drive_path.*local_dir"
  )
})

test_that("drive_path without adapter -> error", {
  expect_error(
    gdpins_init_board(
      name = "x",
      drive_path = "some/path",
      cache_dir = withr::local_tempdir()
    ),
    "adapter.*required"
  )
})

test_that("drive_path without cache_dir -> error", {
  adapter <- gdpins_fake_drive(root = withr::local_tempdir())
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )
  expect_error(
    gdpins_init_board(
      name = "x",
      drive_path = "some/path",
      adapter = adapter
    ),
    "cache_dir.*required"
  )
})

# ── 9. S3 print / format / summary ───────────────────────────────────────────

test_that("format.gdpins_board returns a string ≤ 80 chars", {
  board <- new_fake_board(config = "local_only")
  fmt <- format(board)
  expect_type(fmt, "character")
  expect_length(fmt, 1L)
  expect_lte(nchar(fmt), 80L)
  expect_match(fmt, "gdpins_board")
})

test_that("format.gdpins_board one-liner snapshot matches pattern", {
  board <- new_fake_board(config = "drive_cache", name = "snapshot_test")
  fmt <- format(board)
  # Should contain key fields
  expect_match(fmt, "drive_cache")
  expect_match(fmt, "snapshot_test")
})

test_that("print.gdpins_board runs without error", {
  board <- new_fake_board(config = "drive_cache_local", name = "printtest")
  # cli writes to message/stderr; just check no error is thrown
  expect_no_error(print(board))
})

test_that("summary.gdpins_board runs without error", {
  board <- new_fake_board(config = "drive_cache", name = "sumtest")
  expect_no_error(summary(board))
})

test_that("print returns board invisibly", {
  board <- new_fake_board(config = "local_only")
  result <- withVisible(print(board))
  expect_false(result$visible)
  expect_identical(result$value, board)
})

test_that("format snapshot: all three config outputs stay ≤80 chars", {
  configs <- c("local_only", "drive_cache", "drive_cache_local")
  for (cfg in configs) {
    b <- new_fake_board(config = cfg, name = "chk")
    fmt <- format(b)
    expect_lte(nchar(fmt), 80L, label = paste("config:", cfg))
  }
})

# ── 10. Additional branch coverage ───────────────────────────────────────────

test_that("versioned=NA -> error", {
  local_dir <- withr::local_tempdir()
  expect_error(
    gdpins_init_board(name = "x", local_dir = local_dir, versioned = NA),
    "non-NA logical scalar"
  )
})

test_that("versioned=non-logical -> error", {
  local_dir <- withr::local_tempdir()
  expect_error(
    gdpins_init_board(name = "x", local_dir = local_dir, versioned = "yes"),
    "non-NA logical scalar"
  )
})

test_that("on_discrepancy=prompt non-interactive -> warns", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  # Tests are non-interactive: prompt falls through to warn
  expect_warning(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "prompt"
    ),
    "sync discrepancy"
  )
})

test_that("sync_from_drive failure is caught and warned", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    gdpins_sync = function(...) stop("sync exploded"),
    .package = "gdpins"
  )
  suppressMessages(
    expect_warning(
      gdpins_init_board(
        name = "x",
        local_dir = local_dir,
        on_discrepancy = "sync_from_drive"
      ),
      "Sync from Drive failed"
    )
  )
})

test_that("sync_to_drive failure is caught and warned", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    gdpins_sync = function(...) stop("sync exploded"),
    .package = "gdpins"
  )
  suppressMessages(
    expect_warning(
      gdpins_init_board(
        name = "x",
        local_dir = local_dir,
        on_discrepancy = "sync_to_drive"
      ),
      "Sync to Drive failed"
    )
  )
})

test_that("format.gdpins_board: board with no drive_path, no local_dir", {
  # Construct manually to hit the else branch (path_str = "")
  board <- new_gdpins_board(
    config = "local_only",
    name = "bare",
    versioned = FALSE
  )
  fmt <- format(board)
  expect_type(fmt, "character")
  expect_lte(nchar(fmt), 80L)
  expect_match(fmt, "v-")
})

test_that("print.gdpins_board: local_only board (no drive_path, no cache_dir)", {
  board <- new_fake_board(config = "local_only", name = "localprint")
  expect_no_error(print(board))
})

test_that("summary.gdpins_board: local_only board (no drive_path, no cache_dir)", {
  board <- new_fake_board(config = "local_only", name = "localsum")
  expect_no_error(summary(board))
})

test_that("drive_cache_local offline with non-existing local_dir -> creates it", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  parent <- withr::local_tempdir()
  local_dir <- file.path(parent, "new_local") # doesn't exist yet
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  expect_warning(
    board <- gdpins_init_board(
      name = "offline_newlocal",
      drive_path = "x/y",
      cache_dir = cache_dir,
      local_dir = local_dir,
      adapter = adapter,
      on_discrepancy = "ignore"
    ),
    "No internet connection"
  )
  expect_true(dir.exists(local_dir))
  expect_equal(board$config, "local_only")
})

test_that("drive_cache board with non-existing cache_dir -> creates it", {
  fake_root <- withr::local_tempdir()
  parent <- withr::local_tempdir()
  cache_dir <- file.path(parent, "new_cache") # doesn't exist yet
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "boards/newcache"

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "newcacheboard",
    drive_path = drive_path,
    cache_dir = cache_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )
  expect_true(dir.exists(cache_dir))
  expect_equal(board$config, "drive_cache")
})

test_that("drive_cache_local with non-existing local_dir -> creates it online", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  parent <- withr::local_tempdir()
  local_dir <- file.path(parent, "new_local_online") # doesn't exist yet
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "boards/supernew"

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "supernew",
    drive_path = drive_path,
    cache_dir = cache_dir,
    local_dir = local_dir,
    adapter = adapter,
    create = TRUE,
    on_discrepancy = "ignore"
  )
  expect_true(dir.exists(local_dir))
  expect_equal(board$config, "drive_cache_local")
})

test_that("drive_cache offline with non-existing cache_dir -> creates it", {
  # Line 250: offline drive_cache where cache_dir does not yet exist
  fake_root <- withr::local_tempdir()
  parent <- withr::local_tempdir()
  cache_dir <- file.path(parent, "new_cache_offline") # doesn't exist
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() FALSE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  expect_warning(
    board <- gdpins_init_board(
      name = "offline_cache_new",
      drive_path = "some/path",
      cache_dir = cache_dir,
      adapter = adapter,
      on_discrepancy = "ignore"
    ),
    "No internet connection"
  )
  expect_true(dir.exists(cache_dir))
  expect_equal(board$config, "local_only")
})

test_that("on_discrepancy=prompt in interactive session -> informs", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  # withr::local_interactive sets interactive mode temporarily
  withr::local_options(list(rlang_interactive = TRUE))
  # In the fake interactive env, prompt branch should message (not warn)
  expect_message(
    gdpins_init_board(
      name = "x",
      local_dir = local_dir,
      on_discrepancy = "prompt"
    ),
    "sync discrepancy"
  )
})

test_that("gdpins_init_board create=NA uses .board_readline not utils::askYesNo", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  withr::local_options(list(rlang_interactive = TRUE))

  testthat::local_mocked_bindings(
    .board_readline = function(prompt) "Yes",
    .package = "gdpins"
  )
  local_mocked_bindings(
    askYesNo = function(...) stop("utils::askYesNo must not be called"),
    .package = "utils"
  )

  board <- gdpins_init_board(
    name = "interactive_create",
    drive_path = "new/interactive/path",
    cache_dir = cache_dir,
    adapter = adapter,
    create = NA,
    on_discrepancy = "ignore"
  )
  expect_s3_class(board, "gdpins_board")
  expect_true(gd_exists(adapter, "new/interactive/path"))
})

test_that("create=NA + interactive + user says NO -> errors", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    .package = "gdpins"
  )

  withr::local_options(list(rlang_interactive = TRUE))

  testthat::local_mocked_bindings(
    .board_readline = function(prompt) "no",
    .package = "gdpins"
  )

  expect_error(
    gdpins_init_board(
      name = "interactive_no",
      drive_path = "new/interactive/no",
      cache_dir = cache_dir,
      adapter = adapter,
      create = NA
    ),
    "Drive board path does not exist"
  )
})

test_that("drive_cache board already exists on fake drive: build succeeds", {
  fake_root <- withr::local_tempdir()
  cache_dir <- withr::local_tempdir()
  adapter <- gdpins_fake_drive(root = fake_root)
  drive_path <- "existing/board"

  # Pre-create the directory so gd_exists returns TRUE
  fs::dir_create(file.path(fake_root, "existing", "board"))

  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )

  board <- gdpins_init_board(
    name = "existing_board",
    drive_path = drive_path,
    cache_dir = cache_dir,
    adapter = adapter,
    create = NA,
    on_discrepancy = "ignore"
  )
  expect_equal(board$config, "drive_cache")
})

# ── .has_discrepancy / .handle_init_sync ──────────────────────────────────────
# Regression: .handle_init_sync() used to fire its on_discrepancy action for any
# non-NULL status, so a fully in-sync (or empty) board warned "sync discrepancy
# detected" on every gdpins_init_board() call, and on_discrepancy = "sync_*"
# re-synced boards that needed nothing.

# The mocks previously used a `status` column where the real schema says
# `state`. Nothing read them, so the drift was invisible. Pin them together.
test_that("mock status fixtures match the real gdpins_board_status() schema", {
  real <- names(.empty_board_status_tbl())
  for (m in list(
    mock_status_ok,
    mock_status_in_sync,
    mock_status_discrepancy,
    mock_status_offline
  )) {
    expect_identical(names(m()), real)
  }
  expect_true("state" %in% real)
  expect_false("status" %in% real)
})

test_that(".has_discrepancy is FALSE for empty and all-in-sync status", {
  expect_false(.has_discrepancy(mock_status_ok()))
  expect_false(.has_discrepancy(mock_status_in_sync()))
  expect_false(.has_discrepancy(NULL))
})

test_that(".has_discrepancy treats offline as 'cannot tell', not drift", {
  expect_false(.has_discrepancy(mock_status_offline()))
})

test_that(".has_discrepancy is TRUE only for actionable states", {
  expect_true(.has_discrepancy(mock_status_discrepancy()))
  for (s in c("local_ahead", "drive_ahead", "conflict")) {
    st <- mock_status_in_sync()
    st$state <- s
    expect_true(.has_discrepancy(st), info = s)
  }
})

test_that("init does not warn when board is in sync (on_discrepancy = 'warn')", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_in_sync(),
    .package = "gdpins"
  )
  expect_no_warning(
    gdpins_init_board(
      name = "quiet",
      local_dir = local_dir,
      on_discrepancy = "warn"
    )
  )
})

test_that("init does not warn when status is empty (nothing on either side)", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_ok(),
    .package = "gdpins"
  )
  expect_no_warning(
    gdpins_init_board(
      name = "empty",
      local_dir = local_dir,
      on_discrepancy = "warn"
    )
  )
})

test_that("init still warns when there IS a real discrepancy", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_discrepancy(),
    .package = "gdpins"
  )
  expect_warning(
    gdpins_init_board(
      name = "drifted",
      local_dir = local_dir,
      on_discrepancy = "warn"
    ),
    "sync discrepancy detected"
  )
})

test_that("init does not warn about discrepancy when offline", {
  local_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_offline(),
    .package = "gdpins"
  )
  expect_no_warning(
    gdpins_init_board(
      name = "offline_board",
      local_dir = local_dir,
      on_discrepancy = "warn"
    )
  )
})

test_that("in-sync board is not re-synced under on_discrepancy = 'sync_from_drive'", {
  local_dir <- withr::local_tempdir()
  synced <- FALSE
  testthat::local_mocked_bindings(
    gdpins_is_online = function() TRUE,
    gdpins_board_status = function(x) mock_status_in_sync(),
    gdpins_sync = function(x, ...) {
      synced <<- TRUE
      invisible(x)
    },
    .package = "gdpins"
  )
  gdpins_init_board(
    name = "nosync",
    local_dir = local_dir,
    on_discrepancy = "sync_from_drive"
  )
  expect_false(synced)
})
