# helper-fakes.R — fake-board test harness (contract §5)
# Depends on: new_gdpins_board(), new_gdpins_raw_conn(), gdpins_fake_drive()
# No network calls. Uses tempdir() for all filesystem state.

#' Create a fake gdpins board wired to a fake drive adapter
#'
#' Returns a real `gdpins_board` object backed entirely by tempdir resources
#' and a `gdpins_fake_drive()` adapter. No network. Fresh tempdirs each call.
#'
#' All three configurations are supported:
#' - `"drive_cache"`: fake drive root + `board_folder` over `<fake_root>/<drive_path>` + cache tempdir.
#' - `"local_only"`: plain `board_folder` over a fresh tempdir.
#' - `"drive_cache_local"` (super): drive + cache + local, all fresh tempdirs.
#'
#' @param config Character scalar. One of `c("drive_cache", "local_only",
#'   "drive_cache_local")`. Default `"drive_cache"`.
#' @param versioned Logical. Whether the board is versioned. Default `TRUE`.
#' @param name Character scalar. Board label. Default `"test"`.
#'
#' @return A `gdpins_board` object.
#' @keywords internal
new_fake_board <- function(
    config    = c("drive_cache", "local_only", "drive_cache_local"),
    versioned = TRUE,
    name      = "test"
) {
  config <- match.arg(config)
  drive_path <- paste0("gdpins-fake/", name)

  if (config == "local_only") {
    local_dir <- tempfile("gdpins_local_")
    fs::dir_create(local_dir)
    local_board <- pins::board_folder(local_dir, versioned = versioned)
    return(new_gdpins_board(
      config      = "local_only",
      name        = name,
      local_board = local_board,
      local_dir   = local_dir,
      versioned   = versioned
    ))
  }

  # Fake drive adapter with its own root
  fake_root <- tempfile("gdpins_fake_drive_")
  fs::dir_create(fake_root)
  adapter <- gdpins_fake_drive(root = fake_root)

  # Drive board: board_folder over <fake_root>/<drive_path>
  drive_board_dir <- file.path(fake_root, gsub("/", .Platform$file.sep, drive_path))
  fs::dir_create(drive_board_dir)
  drive_board <- pins::board_folder(drive_board_dir, versioned = versioned)

  # Cache board: separate tempdir
  cache_dir <- tempfile("gdpins_cache_")
  fs::dir_create(cache_dir)
  cache_board <- pins::board_folder(cache_dir, versioned = versioned)

  if (config == "drive_cache") {
    return(new_gdpins_board(
      config      = "drive_cache",
      name        = name,
      drive_board = drive_board,
      cache_board = cache_board,
      cache_dir   = cache_dir,
      drive_path  = drive_path,
      adapter     = adapter,
      versioned   = versioned
    ))
  }

  # drive_cache_local (super): also has a standalone local board
  local_dir <- tempfile("gdpins_local_")
  fs::dir_create(local_dir)
  local_board <- pins::board_folder(local_dir, versioned = versioned)

  new_gdpins_board(
    config      = "drive_cache_local",
    name        = name,
    drive_board = drive_board,
    cache_board = cache_board,
    local_board = local_board,
    cache_dir   = cache_dir,
    local_dir   = local_dir,
    drive_path  = drive_path,
    adapter     = adapter,
    versioned   = versioned
  )
}

#' Create a fake gdpins_raw_conn wired to a fake drive adapter
#'
#' Returns a real `gdpins_raw_conn` object backed entirely by tempdir
#' resources. No network.
#'
#' @param config Character scalar. One of `c("drive_local", "local_only")`.
#'   Default `"drive_local"`.
#'
#' @return A `gdpins_raw_conn` object.
#' @keywords internal
new_fake_raw_conn <- function(
    config = c("drive_local", "local_only")
) {
  config <- match.arg(config)

  local_path <- tempfile("gdpins_raw_local_")
  fs::dir_create(local_path)

  if (config == "local_only") {
    return(new_gdpins_raw_conn(
      config     = "local_only",
      local_path = local_path
    ))
  }

  # drive_local: fake adapter
  fake_root <- tempfile("gdpins_fake_drive_")
  fs::dir_create(fake_root)
  adapter    <- gdpins_fake_drive(root = fake_root)
  drive_path <- "gdpins-fake/raw-exogenous"

  new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = drive_path,
    local_path = local_path,
    adapter    = adapter
  )
}

# ── gdpins_board_status() mocks ───────────────────────────────────────────────
# Single source of truth for fake status tibbles, shared by test-board.R and
# test-offline.R. Each test file gets its own environment, so a mock defined in
# a test file is invisible to the others -- copies drift.
#
# The schema is taken from the package's own .empty_board_status_tbl() instead
# of being hand-written, and mock_status_row() asserts against it. It drifted
# once: the mocks carried a `status` column where the real schema says `state`.
# Because .handle_init_sync() acted on any non-NULL status, nothing ever read
# the mock, and every "warns on drift" test passed for the wrong reason. If the
# real schema moves again, these fixtures fail loudly rather than silently.

mock_status_ok <- function() .empty_board_status_tbl()

mock_status_row <- function(name          = "some_pin",
                            state         = "in_sync",
                            drive_version = "20260101T120000Z-aaa",
                            local_version = "20260101T120000Z-aaa",
                            drive_hash    = "aaaa",
                            local_hash    = "aaaa") {
  row <- tibble::tibble(
    name          = name,
    state         = state,
    drive_version = drive_version,
    local_version = local_version,
    drive_created = list(as.POSIXct("2026-01-01 12:00:00", tz = "UTC")),
    local_created = list(as.POSIXct("2026-01-02 12:00:00", tz = "UTC")),
    drive_hash    = drive_hash,
    local_hash    = local_hash
  )
  stopifnot(identical(names(row), names(.empty_board_status_tbl())))
  row
}

# Local side has a newer version -- a real, actionable discrepancy.
mock_status_discrepancy <- function() {
  mock_status_row(
    state         = "local_ahead",
    local_version = "20260102T120000Z-bbb",
    local_hash    = "bbbb"
  )
}

# Status call succeeded, but nothing needs reconciling.
mock_status_in_sync <- function() mock_status_row(state = "in_sync")

# Could not be compared at all -- not a discrepancy.
mock_status_offline <- function() {
  mock_status_row(
    state         = "offline",
    drive_version = NA_character_,
    local_version = NA_character_,
    drive_hash    = NA_character_,
    local_hash    = NA_character_
  )
}
