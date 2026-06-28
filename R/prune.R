#' Version pruning with delete guards
#'
#' Functions for pruning old pin versions from boards. All Drive removals use
#' `gd_trash()` (recoverable; never hard-deletes). Cache removals delete local
#' directory trees. Raw files are **never** auto-deleted by any function —
#' removal is manual outside R.
#'
#' @name prune
NULL

# ── internal helpers ──────────────────────────────────────────────────────────

#' Resolve the authoritative sub-board for a given config
#'
#' For `drive_cache` / `drive_cache_local`: Drive board is authoritative for
#' reporting the removed version labels. For `local_only`: local board is the
#' only board.
#'
#' @param board A `gdpins_board` object.
#' @return A `pins` board object.
#' @keywords internal
.prune_primary_board <- function(board) {
  if (!is.null(board$drive_board)) board$drive_board else board$local_board
}

#' Compute version labels to remove for a given sub-board (oldest, keeping newest)
#'
#' `pins::pin_versions()` returns rows sorted ascending by `created` (oldest
#' first, newest last). We keep the last `keep` rows and remove the rest.
#' Each sub-board (drive, cache, local) may have slightly different timestamp
#' prefixes in version labels even for the same logical version, so each board
#' must compute its own removal list independently.
#'
#' @param sub_board A `pins` board.
#' @param name Pin name.
#' @param keep Integer. Number of newest versions to keep.
#' @return Character vector of version labels to remove (may be empty).
#' @keywords internal
.versions_to_remove <- function(sub_board, name, keep) {
  v <- pins::pin_versions(sub_board, name)
  n <- nrow(v)
  if (n <= keep) return(character(0L))
  v$version[seq_len(n - keep)]
}

#' Trash one version directory from Drive via the adapter
#'
#' Constructs the adapter-relative path `<drive_path>/<name>/<version>` and
#' calls `gd_trash()`.
#'
#' @param adapter A `gdpins_drive_adapter`.
#' @param drive_path Character. Board drive path (relative to adapter root).
#' @param name Pin name.
#' @param version Version label.
#' @keywords internal
.trash_drive_version <- function(adapter, drive_path, name, version) {
  rel_path <- paste(drive_path, name, version, sep = "/")
  gd_trash(adapter, rel_path)
}

#' Remove one version directory from a local board (cache or local_only)
#'
#' Directly unlinks the version subdirectory under `board_path/<name>/<version>`.
#'
#' @param board_path Character. Local path to the `pins` board_folder root.
#' @param name Pin name.
#' @param version Version label.
#' @keywords internal
.remove_local_version <- function(board_path, name, version) {
  dir_path <- file.path(board_path, name, version)
  if (fs::dir_exists(dir_path)) {
    fs::dir_delete(dir_path)
  }
}

#' Thin wrapper around base::interactive() for testability
#'
#' Isolating the call lets tests mock `.prune_is_interactive()` at the
#' package level without patching `base::interactive`.
#'
#' @return Logical scalar.
#' @keywords internal
.prune_is_interactive <- function() interactive()

#' Thin wrapper around base::readline() for testability
#'
#' Isolating the call lets tests mock `.prune_readline()` at the package
#' level without patching `base::readline`.
#'
#' @param prompt Character scalar prompt string.
#' @return Character scalar (user input).
#' @keywords internal
.prune_readline <- function(prompt) readline(prompt)

#' Confirm a bulk removal when threshold is exceeded
#'
#' In interactive sessions, prompts the user. Non-interactively (or if the
#' user declines), calls `cli::cli_abort()`.
#'
#' @param n_remove Integer. Number of versions that would be removed.
#' @param threshold Integer. Configured removal threshold.
#' @param context Character scalar. Context description shown in the prompt
#'   (e.g. `"pin 'mypin'"` or `"board 'test' across 3 pins"`).
#' @keywords internal
.prune_check_threshold <- function(n_remove, threshold, context) {
  if (.prune_is_interactive()) {
    answer <- .prune_readline(cli::format_inline(
      "About to remove {n_remove} version{?s} for {context} ",
      "(threshold = {threshold}). Proceed? [y/N]: "
    ))
    if (!identical(tolower(trimws(answer)), "y")) {
      cli::cli_abort(c(
        "Pruning aborted: {n_remove} removal{?s} exceed{?s/} threshold of {threshold}.",
        i = "Pass {.code force = TRUE} to skip this check non-interactively."
      ))
    }
  } else {
    cli::cli_abort(c(
      "Pruning aborted: {n_remove} removal{?s} exceed{?s/} threshold of {threshold}.",
      i = "Pass {.code force = TRUE} to skip this check non-interactively.",
      i = "Or raise {.arg threshold} / lower {.arg keep}."
    ))
  }
}

# ── exported functions ────────────────────────────────────────────────────────

#' Prune old versions of a single pin
#'
#' Removes old versions of one pin from Drive **and** cache (or local board),
#' keeping the `keep` most recent. Drive versions are always **trashed**
#' (recoverable via `gd_trash()`), never hard-deleted. Cache versions are
#' deleted from the local filesystem.
#'
#' Defaults to `dry_run = TRUE` for safety: the plan is shown but nothing is
#' removed.
#'
#' Deleting more than `threshold` versions in a single call requires either
#' interactive confirmation or `force = TRUE`. The threshold check is skipped
#' during a dry run.
#'
#' **Raw files are never auto-deleted by any function** — removal is manual
#' outside R.
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name.
#' @param keep Integer scalar. Number of most-recent versions to keep. Default
#'   `1`.
#' @param dry_run Logical. If `TRUE` (default), show what would be removed
#'   without actually removing anything.
#' @param threshold Integer scalar. Maximum number of versions to remove without
#'   requiring `force = TRUE` or interactive confirmation. Default `10`.
#' @param force Logical. If `TRUE`, skip the interactive threshold confirmation.
#'   Default `FALSE`.
#'
#' @return Invisibly, a character vector of the version labels that were (or
#'   would be) removed (as reported by the primary / Drive board).
#' @export
gdpins_prune_pin_versions <- function(
    board,
    name,
    keep      = 1,
    dry_run   = TRUE,
    threshold = 10,
    force     = FALSE
) {
  # ── input validation ──────────────────────────────────────────────────────
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board} object.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  keep <- as.integer(keep)
  if (length(keep) != 1L || is.na(keep) || keep < 1L) {
    cli::cli_abort(c(
      "{.arg keep} must be a positive integer >= 1.",
      x = "Got {.val {keep}}."
    ))
  }

  # ── determine old versions from the primary (authoritative) board ─────────
  # The primary board (Drive or local_only) determines the reported version
  # labels. Each sub-board prunes independently because version timestamps may
  # differ slightly even for the same logical write.
  primary      <- .prune_primary_board(board)
  old_versions <- .versions_to_remove(primary, name, keep)
  n_remove     <- length(old_versions)

  if (n_remove == 0L) {
    cli::cli_inform(c(
      i = "No versions to remove for pin {.val {name}} ({keep} kept, {keep} present)."
    ))
    return(invisible(character(0L)))
  }

  # ── dry run: show plan, change nothing ───────────────────────────────────
  if (dry_run) {
    cli::cli_inform(c(
      i = "DRY RUN — would remove {n_remove} version{?s} of pin {.val {name}}:",
      " " = paste(old_versions, collapse = "\n  ")
    ))
    return(invisible(old_versions))
  }

  # ── threshold guard (only for actual removals) ────────────────────────────
  if (n_remove > threshold && !force) {
    .prune_check_threshold(n_remove, threshold, paste0("pin '", name, "'"))
  }

  # ── perform removals — each board prunes its own version list ────────────
  # Each sub-board independently determines which of its versions are "old"
  # (i.e., all but the newest `keep`). This is necessary because pins generates
  # version labels from timestamp + content hash, and the timestamp may differ
  # by a second between drive_board and cache_board writes.
  config <- board$config

  if (config %in% c("drive_cache", "drive_cache_local")) {
    # Trash old versions from Drive (recoverable — NEVER hard-delete)
    drive_old <- .versions_to_remove(board$drive_board, name, keep)
    for (v in drive_old) {
      .trash_drive_version(board$adapter, board$drive_path, name, v)
    }
    # Remove old versions from cache (local filesystem)
    cache_old <- .versions_to_remove(board$cache_board, name, keep)
    for (v in cache_old) {
      .remove_local_version(board$cache_board$path, name, v)
    }
  }
  if (config == "drive_cache_local") {
    # Also remove from standalone local board
    local_old <- .versions_to_remove(board$local_board, name, keep)
    for (v in local_old) {
      .remove_local_version(board$local_board$path, name, v)
    }
  }
  if (config == "local_only") {
    local_old <- .versions_to_remove(board$local_board, name, keep)
    for (v in local_old) {
      .remove_local_version(board$local_board$path, name, v)
    }
  }

  cli::cli_inform(c(
    v = "Pruned {n_remove} old version{?s} of pin {.val {name}}."
  ))

  invisible(old_versions)
}

#' Prune old versions of all pins in a board
#'
#' Applies [gdpins_prune_pin_versions()] to every pin in `board`. Defaults to
#' `dry_run = TRUE`.
#'
#' @param board A `gdpins_board` object.
#' @param keep Integer scalar. Versions to keep per pin. Default `1`.
#' @param dry_run Logical. Show plan without removing. Default `TRUE`.
#' @param threshold Integer scalar. Threshold before requiring confirmation.
#'   Default `10`.
#' @param force Logical. Skip interactive confirmation. Default `FALSE`.
#'
#' @return Invisibly, a named list of character vectors (one per pin) of
#'   removed (or would-be-removed) version labels.
#' @export
gdpins_prune_board_versions <- function(
    board,
    keep      = 1,
    dry_run   = TRUE,
    threshold = 10,
    force     = FALSE
) {
  # ── input validation ──────────────────────────────────────────────────────
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board} object.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  keep <- as.integer(keep)
  if (length(keep) != 1L || is.na(keep) || keep < 1L) {
    cli::cli_abort(c(
      "{.arg keep} must be a positive integer >= 1.",
      x = "Got {.val {keep}}."
    ))
  }

  # ── enumerate pins ────────────────────────────────────────────────────────
  primary  <- .prune_primary_board(board)
  all_pins <- pins::pin_list(primary)

  if (length(all_pins) == 0L) {
    cli::cli_inform(c(i = "No pins found in board {.val {board$name}}."))
    return(invisible(list()))
  }

  # ── pre-flight threshold check (actual removal only) ─────────────────────
  # Compute removals for every pin up front so we can abort before touching
  # anything if any pin would exceed the threshold.
  if (!dry_run && !force) {
    removals <- lapply(all_pins, function(nm) .versions_to_remove(primary, nm, keep))
    names(removals) <- all_pins
    exceeding <- names(Filter(function(v) length(v) > threshold, removals))

    if (length(exceeding) > 0L) {
      total <- sum(vapply(removals, length, integer(1L)))
      context <- cli::format_inline(
        "board '{board$name}' ({length(all_pins)} pin{?s}, {total} total removal{?s})"
      )
      .prune_check_threshold(total, threshold, context)
    }
  }

  # ── prune each pin (threshold already cleared above) ─────────────────────
  result <- lapply(all_pins, function(nm) {
    gdpins_prune_pin_versions(
      board     = board,
      name      = nm,
      keep      = keep,
      dry_run   = dry_run,
      threshold = threshold,
      force     = TRUE  # threshold already checked; skip per-pin re-check
    )
  })
  names(result) <- all_pins

  invisible(result)
}
