# helper-fakes.R — fake-board test harness (contract §5)
# Depends on: new_gdpins_board(), new_gdpins_raw_conn(), gdpins_fake_drive()
# No network calls. Uses tempdir() for all filesystem state.

#' Create a fake gdpins board wired to a fake drive adapter
#'
#' Returns a real `gdpins_board` object backed entirely by tempdir resources
#' and a `gdpins_fake_drive()` adapter. No network. Fresh tempdirs each call.
#'
#' All three configurations are supported:
#' - `"drive_cache"`: fake drive root + `board_folder` over `<fake_root>/<drive_path>`,
#'   plus a `local_board` (the one local copy) over a fresh `cache_dir` tempdir.
#' - `"local_only"`: plain `board_folder` over a fresh tempdir (`local_board`,
#'   `cache_dir` both point at it); no drive.
#' - `"drive_only"`: fake drive root + drive board only; no local copy
#'   (`local_board` and `cache_dir` are `NULL`).
#'
#' @param config Character scalar. One of `c("drive_cache", "local_only",
#'   "drive_only")`. Default `"drive_cache"`.
#' @param versioned Logical. Whether the board is versioned. Default `TRUE`.
#' @param name Character scalar. Board label. Default `"test"`.
#'
#' @return A `gdpins_board` object.
#' @keywords internal
new_fake_board <- function(
    config    = c("drive_cache", "local_only", "drive_only"),
    versioned = TRUE,
    name      = "test"
) {
  config <- match.arg(config)
  drive_path <- paste0("gdpins-fake/", name)

  if (config == "local_only") {
    cache_dir <- tempfile("gdpins_local_")
    fs::dir_create(cache_dir)
    local_board <- pins::board_folder(cache_dir, versioned = versioned)
    return(new_gdpins_board(
      config      = "local_only",
      name        = name,
      local_board = local_board,
      cache_dir   = cache_dir,
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

  if (config == "drive_only") {
    return(new_gdpins_board(
      config      = "drive_only",
      name        = name,
      drive_board = drive_board,
      local_board = NULL,
      cache_dir   = NULL,
      drive_path  = drive_path,
      adapter     = adapter,
      versioned   = versioned
    ))
  }

  # drive_cache: drive board + the one local copy, over a fresh tempdir
  cache_dir <- tempfile("gdpins_cache_")
  fs::dir_create(cache_dir)
  local_board <- pins::board_folder(cache_dir, versioned = versioned)

  new_gdpins_board(
    config      = "drive_cache",
    name        = name,
    drive_board = drive_board,
    local_board = local_board,
    cache_dir   = cache_dir,
    drive_path  = drive_path,
    adapter     = adapter,
    versioned   = versioned
  )
}

# ── Sandboxed fixtures ────────────────────────────────────────────────────────
# new_fake_board()/new_fake_raw_conn() put their directories directly inside the
# session tempdir(). Tests that feed path-escaping names ("..", ".") must never
# use them: on unfixed code such a name deletes or writes into tempdir() itself.
# These variants build everything under sub-directories of `parent` (normally a
# withr::local_tempdir()), so the worst an escape can reach is `parent`.
#
#   <parent>/cache            local board (local_only, drive_cache)
#   <parent>/fake_drive       fake Drive root (drive_cache, drive_only)
#   <parent>/mirror           raw connection local_path
#
# Raw connections use drive_path "gdpins-fake/raw-exogenous", so the Drive side
# of a raw file `f` is <parent>/fake_drive/gdpins-fake/raw-exogenous/<f>.

new_sandboxed_board <- function(
    parent,
    config    = c("local_only", "drive_cache", "drive_only"),
    versioned = TRUE,
    name      = "test"
) {
  config <- match.arg(config)
  drive_path <- paste0("gdpins-fake/", name)

  cache_dir <- file.path(parent, "cache")
  if (config == "local_only") {
    fs::dir_create(cache_dir)
    return(new_gdpins_board(
      config      = "local_only",
      name        = name,
      local_board = pins::board_folder(cache_dir, versioned = versioned),
      cache_dir   = cache_dir,
      versioned   = versioned
    ))
  }

  fake_root <- file.path(parent, "fake_drive")
  adapter   <- gdpins_fake_drive(root = fake_root)
  drive_dir <- file.path(fake_root, "gdpins-fake", name)
  fs::dir_create(drive_dir)
  drive_board <- pins::board_folder(drive_dir, versioned = versioned)

  if (config == "drive_only") {
    return(new_gdpins_board(
      config      = "drive_only",
      name        = name,
      drive_board = drive_board,
      drive_path  = drive_path,
      adapter     = adapter,
      versioned   = versioned
    ))
  }

  fs::dir_create(cache_dir)
  new_gdpins_board(
    config      = "drive_cache",
    name        = name,
    drive_board = drive_board,
    local_board = pins::board_folder(cache_dir, versioned = versioned),
    cache_dir   = cache_dir,
    drive_path  = drive_path,
    adapter     = adapter,
    versioned   = versioned
  )
}

new_sandboxed_raw_conn <- function(
    parent,
    config = c("drive_local", "local_only")
) {
  config <- match.arg(config)

  local_path <- file.path(parent, "mirror")
  fs::dir_create(local_path)

  if (config == "local_only") {
    return(new_gdpins_raw_conn(config = "local_only", local_path = local_path))
  }

  fake_root  <- file.path(parent, "fake_drive")
  adapter    <- gdpins_fake_drive(root = fake_root)
  drive_path <- "gdpins-fake/raw-exogenous"
  fs::dir_create(file.path(fake_root, "gdpins-fake", "raw-exogenous"))

  new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = drive_path,
    local_path = local_path,
    adapter    = adapter
  )
}

# Every path under `dir` (recursive, hidden included) -- a cheap fingerprint
# for "this call did not touch storage".
sandbox_listing <- function(dir) {
  sort(as.character(fs::dir_ls(dir, recurse = TRUE, all = TRUE)))
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

# ── Real-adapter fixtures ─────────────────────────────────────────────────────
# A minimal stand-in for a googledrive dribble: the columns the real adapter
# reads (`name`, `id`, `drive_resource` with mimeType / md5Checksum /
# modifiedTime / size). Vectorised over `name`; used with
# local_mocked_bindings(..., .package = "googledrive").

fake_dribble <- function(name    = character(),
                         id      = paste0("id_", name),
                         mime    = "text/csv",
                         md5     = "d41d8cd98f00b204e9800998ecf8427e",
                         mtime   = "2024-01-01T00:00:00.000Z") {
  n <- length(name)
  mime  <- rep_len(mime, n)
  md5   <- rep_len(md5, n)
  mtime <- rep_len(mtime, n)
  tibble::tibble(
    name = as.character(name),
    id   = as.character(id),
    drive_resource = lapply(seq_len(n), function(i) list(
      kind         = "drive#file",
      mimeType     = mime[[i]],
      md5Checksum  = md5[[i]],
      modifiedTime = mtime[[i]],
      size         = "10"
    ))
  )
}

fake_folder_dribble <- function(name, id = paste0("id_", name)) {
  fake_dribble(name, id, mime = "application/vnd.google-apps.folder")
}
