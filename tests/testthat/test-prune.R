# test-prune.R — TDD tests for R/prune.R (WS6)
# Uses new_fake_board(versioned=TRUE); seeds versions directly via
# repeated pins::pin_write() calls on drive_board and cache_board.
# No network. No dependency on WS3 verbs.

# ── Helpers ───────────────────────────────────────────────────────────────────

# Seed n versions of `name` into both drive_board and cache_board of `board`.
seed_versions <- function(board, name, n) {
  for (i in seq_len(n)) {
    if (!is.null(board$drive_board)) {
      pins::pin_write(board$drive_board, data.frame(v = i), name)
    }
    if (!is.null(board$cache_board)) {
      pins::pin_write(board$cache_board, data.frame(v = i), name)
    }
    if (!is.null(board$local_board) && is.null(board$drive_board)) {
      pins::pin_write(board$local_board, data.frame(v = i), name)
    }
  }
  invisible(board)
}

# Count versions on a given sub-board
count_versions <- function(sub_board, name) {
  nrow(pins::pin_versions(sub_board, name))
}

# ── dry_run (default) ─────────────────────────────────────────────────────────

test_that("dry_run shows plan and changes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = TRUE)

  # Returns the 2 old version labels that WOULD be removed
  expect_length(result, 2L)
  expect_type(result, "character")

  # Nothing was actually removed — still 3 on both boards
  expect_equal(count_versions(board$drive_board, "mypin"), 3L)
  expect_equal(count_versions(board$cache_board, "mypin"), 3L)
})

test_that("dry_run=TRUE is the default", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 2)

  # Call without specifying dry_run -> should default to TRUE (no removal)
  gdpins_prune_pin_versions(board, "mypin", keep = 1)

  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$cache_board, "mypin"), 2L)
})

test_that("dry_run=FALSE with nothing to prune returns empty character vector", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 1)  # only 1 version, keep=1 -> nothing to remove

  result <- gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  expect_length(result, 0L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

# ── actual prune — keeps newest keep, removes older ──────────────────────────

test_that("removes old versions from Drive and cache", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 4)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 2, dry_run = FALSE
  )

  # 2 old versions removed
  expect_length(result, 2L)
  # Drive and cache each now have 2 versions
  expect_equal(count_versions(board$drive_board, "mypin"), 2L)
  expect_equal(count_versions(board$cache_board, "mypin"), 2L)
})

test_that("returns the removed version labels", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v <- pins::pin_versions(board$drive_board, "mypin")$version
  # Newest-last: all_v[3] is newest; all_v[1], all_v[2] are old
  old_expected <- sort(all_v[seq_len(length(all_v) - 1L)])

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE
  )

  expect_setequal(result, old_expected)
})

test_that("keeps the newest versions after pruning", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 4)

  all_v_before <- pins::pin_versions(board$drive_board, "mypin")$version

  gdpins_prune_pin_versions(board, "mypin", keep = 2, dry_run = FALSE)

  remaining_v <- pins::pin_versions(board$drive_board, "mypin")$version
  # The 2 remaining should be the 2 newest (last 2 in ascending-sorted list)
  expect_setequal(
    remaining_v,
    tail(sort(all_v_before), 2L)
  )
})

test_that("keep >= n_versions removes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 5, dry_run = FALSE
  )

  expect_length(result, 0L)
  expect_equal(count_versions(board$drive_board, "mypin"), 3L)
})

# ── TRASH not hard-delete ─────────────────────────────────────────────────────

test_that("trashes Drive versions into adapter trash store (recoverable)", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v_before <- pins::pin_versions(board$drive_board, "mypin")$version
  old_v <- head(sort(all_v_before), 2L)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  adapter <- board$adapter
  trash_keys <- names(adapter$state$trash)

  # Each trashed version should appear in the adapter's trash store
  for (v in old_v) {
    expected_path <- paste0(board$drive_path, "/mypin/", v)
    expect_true(
      any(startsWith(trash_keys, expected_path)),
      info = paste("Expected trash key for version:", v)
    )
  }
})

test_that("trashed dirs are NOT hard-deleted — remain in trash store on disk", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  all_v <- pins::pin_versions(board$drive_board, "mypin")$version
  old_v <- head(sort(all_v), 2L)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Trash store entries must physically exist on disk (moved, not deleted)
  for (k in names(board$adapter$state$trash)) {
    trash_entry <- board$adapter$state$trash[[k]]
    expect_true(
      file.exists(trash_entry),
      info = paste("Trashed item must still exist on disk:", trash_entry)
    )
  }
})

# ── cache removal (local fs unlink, not trash) ────────────────────────────────

test_that("removes old versions from cache dir", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Cache should now have only 1 version
  expect_equal(count_versions(board$cache_board, "mypin"), 1L)
})

# ── threshold guard ───────────────────────────────────────────────────────────

test_that("aborts when removal > threshold and force=FALSE", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)  # 14 removals > threshold=10

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing was removed
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

test_that("proceeds when force=TRUE even above threshold", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = TRUE
  )

  expect_length(result, 14L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("allows removal at exactly threshold (no force needed)", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 11)  # 11 versions, keep=1 -> 10 removals == threshold

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_length(result, 10L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("threshold abort leaves Drive and cache unchanged", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    )
  )

  # Both boards still untouched
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
  expect_equal(count_versions(board$cache_board, "mypin"), 15L)
})

# ── dry_run + threshold interaction ──────────────────────────────────────────

test_that("dry_run skips threshold check entirely", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  # dry_run=TRUE should NOT raise error even when > threshold
  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = TRUE,
    threshold = 10, force = FALSE
  )

  # Shows what would be removed
  expect_length(result, 14L)
  # Removes nothing
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

# ── board-level prune ─────────────────────────────────────────────────────────

test_that("gdpins_prune_board_versions prunes all pins in the board", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "pin_a", 4)
  seed_versions(board, "pin_b", 3)

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE
  )

  expect_named(result, c("pin_a", "pin_b"), ignore.order = TRUE)
  expect_length(result[["pin_a"]], 3L)
  expect_length(result[["pin_b"]], 2L)

  expect_equal(count_versions(board$drive_board, "pin_a"), 1L)
  expect_equal(count_versions(board$drive_board, "pin_b"), 1L)
  expect_equal(count_versions(board$cache_board, "pin_a"), 1L)
  expect_equal(count_versions(board$cache_board, "pin_b"), 1L)
})

test_that("gdpins_prune_board_versions dry_run shows plan and changes nothing", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "alpha", 3)
  seed_versions(board, "beta", 2)

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = TRUE)

  expect_named(result, c("alpha", "beta"), ignore.order = TRUE)
  # Nothing removed
  expect_equal(count_versions(board$drive_board, "alpha"), 3L)
  expect_equal(count_versions(board$drive_board, "beta"), 2L)
})

test_that("gdpins_prune_board_versions returns named list", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "p1", 2)

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_type(result, "list")
  expect_named(result, "p1")
})

test_that("gdpins_prune_board_versions threshold blocks oversized per-pin removal", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big",    15)  # 14 removals > threshold=10
  seed_versions(board, "small",   3)  # 2 removals <= threshold=10

  expect_error(
    gdpins_prune_board_versions(
      board, keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing removed from either pin
  expect_equal(count_versions(board$drive_board, "big"),   15L)
  expect_equal(count_versions(board$drive_board, "small"),  3L)
})

test_that("gdpins_prune_board_versions force=TRUE bypasses threshold for all pins", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big",   15)
  seed_versions(board, "small",  3)

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE,
    threshold = 10, force = TRUE
  )

  expect_equal(count_versions(board$drive_board, "big"),   1L)
  expect_equal(count_versions(board$drive_board, "small"), 1L)
})

test_that("gdpins_prune_board_versions works on local_only board (no adapter)", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  pins::pin_write(board$local_board, data.frame(v = 1), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 2), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 3), "lpin")

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_named(result, "lpin")
  expect_length(result[["lpin"]], 2L)
  expect_equal(count_versions(board$local_board, "lpin"), 1L)
})

# ── local_only board single-pin prune ─────────────────────────────────────────

test_that("gdpins_prune_pin_versions works on local_only board", {
  board <- new_fake_board(config = "local_only", versioned = TRUE)
  pins::pin_write(board$local_board, data.frame(v = 1), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 2), "lpin")
  pins::pin_write(board$local_board, data.frame(v = 3), "lpin")

  result <- gdpins_prune_pin_versions(
    board, "lpin", keep = 1, dry_run = FALSE
  )

  expect_length(result, 2L)
  expect_equal(count_versions(board$local_board, "lpin"), 1L)
})

# ── return value invisibility ─────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions returns invisibly", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  expect_invisible(
    gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)
  )
})

test_that("gdpins_prune_board_versions returns invisibly", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 3)

  expect_invisible(
    gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)
  )
})

# ── input validation ──────────────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions errors on non-gdpins_board", {
  expect_error(
    gdpins_prune_pin_versions("not_a_board", "mypin"),
    regexp = "gdpins_board"
  )
})

test_that("gdpins_prune_board_versions errors on non-gdpins_board", {
  expect_error(
    gdpins_prune_board_versions("not_a_board"),
    regexp = "gdpins_board"
  )
})

test_that("gdpins_prune_pin_versions errors when keep < 1", {
  board <- new_fake_board(versioned = TRUE)
  expect_error(
    gdpins_prune_pin_versions(board, "mypin", keep = 0),
    regexp = "keep"
  )
})

test_that("gdpins_prune_board_versions errors when keep < 1", {
  board <- new_fake_board(versioned = TRUE)
  expect_error(
    gdpins_prune_board_versions(board, keep = 0),
    regexp = "keep"
  )
})

# ── drive_cache_local config ──────────────────────────────────────────────────

test_that("gdpins_prune_pin_versions removes from all three boards in drive_cache_local", {
  board <- new_fake_board(config = "drive_cache_local", versioned = TRUE)
  # Seed into drive, cache, and local
  for (i in 1:3) {
    pins::pin_write(board$drive_board, data.frame(v = i), "mypin")
    pins::pin_write(board$cache_board, data.frame(v = i), "mypin")
    pins::pin_write(board$local_board, data.frame(v = i), "mypin")
  }

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
  expect_equal(count_versions(board$cache_board,  "mypin"), 1L)
  expect_equal(count_versions(board$local_board,  "mypin"), 1L)
})

test_that("gdpins_prune_pin_versions drive_cache_local trashes from Drive", {
  board <- new_fake_board(config = "drive_cache_local", versioned = TRUE)
  for (i in 1:3) {
    pins::pin_write(board$drive_board, data.frame(v = i), "mypin")
    pins::pin_write(board$cache_board, data.frame(v = i), "mypin")
    pins::pin_write(board$local_board, data.frame(v = i), "mypin")
  }

  gdpins_prune_pin_versions(board, "mypin", keep = 1, dry_run = FALSE)

  # Two old versions must appear in the adapter's trash store
  trash_keys <- names(board$adapter$state$trash)
  expect_true(length(trash_keys) >= 2L)
})

# ── empty board ───────────────────────────────────────────────────────────────

test_that("gdpins_prune_board_versions returns empty list for board with no pins", {
  board <- new_fake_board(versioned = TRUE)
  # Do not write any pins

  result <- gdpins_prune_board_versions(board, keep = 1, dry_run = FALSE)

  expect_type(result, "list")
  expect_length(result, 0L)
})

# ── interactive threshold prompt (mocked) ────────────────────────────────────

test_that("gdpins_prune_pin_versions interactive prompt 'y' proceeds", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  # Mock the package-level wrapper so interactive() appears TRUE
  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "y",
    .package              = "gdpins"
  )

  result <- gdpins_prune_pin_versions(
    board, "mypin", keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_length(result, 14L)
  expect_equal(count_versions(board$drive_board, "mypin"), 1L)
})

test_that("gdpins_prune_pin_versions interactive prompt 'N' aborts", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "mypin", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "N",
    .package              = "gdpins"
  )

  expect_error(
    gdpins_prune_pin_versions(
      board, "mypin", keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  # Nothing removed
  expect_equal(count_versions(board$drive_board, "mypin"), 15L)
})

test_that("gdpins_prune_board_versions interactive prompt 'y' proceeds", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "y",
    .package              = "gdpins"
  )

  result <- gdpins_prune_board_versions(
    board, keep = 1, dry_run = FALSE,
    threshold = 10, force = FALSE
  )

  expect_equal(count_versions(board$drive_board, "big"), 1L)
})

test_that("gdpins_prune_board_versions interactive prompt 'N' aborts", {
  board <- new_fake_board(versioned = TRUE)
  seed_versions(board, "big", 15)

  local_mocked_bindings(
    .prune_is_interactive = function() TRUE,
    .prune_readline       = function(prompt) "N",
    .package              = "gdpins"
  )

  expect_error(
    gdpins_prune_board_versions(
      board, keep = 1, dry_run = FALSE,
      threshold = 10, force = FALSE
    ),
    regexp = "force"
  )

  expect_equal(count_versions(board$drive_board, "big"), 15L)
})

# ── internal helper coverage ──────────────────────────────────────────────────

test_that(".prune_readline delegates to base readline", {
  # Mock base::readline to avoid interactive requirement
  local_mocked_bindings(
    readline = function(prompt) paste0("echo:", prompt),
    .package = "base"
  )
  result <- gdpins:::.prune_readline("test prompt")
  expect_identical(result, "echo:test prompt")
})
