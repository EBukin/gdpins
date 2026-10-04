#' Version pruning with delete guards
#'
#' Functions for pruning old pin versions from boards. All Drive removals use
#' `gd_trash()` (recoverable; never hard-deletes). Local-copy removals delete
#' local directory trees. Raw files are **never** auto-deleted by any function
#' -- removal is manual outside R.
#'
#' @name prune
NULL

# -- internal helpers ----------------------------------------------------------

#' Resolve the authoritative sub-board for a given config
#'
#' For Drive boards (`drive_cache`, `drive_only`): Drive board is the one
#' whose pins are enumerated by board-level pruning. For `local_only`: the local copy
#' is the only board.
#'
#' @param board A `gdpins_board` object.
#' @return A `pins` board object.
#' @keywords internal
.prune_primary_board <- function(board) {
  if (!is.null(board$drive_board)) board$drive_board else board$local_board
}

#' An empty prune plan
#'
#' @return A 0-row tibble with the prune plan columns `name`, `version`,
#'   `side`, `hash` and `action`.
#' @keywords internal
.empty_prune_plan <- function() {
  tibble::tibble(
    name    = character(),
    version = character(),
    side    = character(),
    hash    = character(),
    action  = character()
  )
}

#' Build prune plan rows
#'
#' @param name Pin name.
#' @param versions A `pins::pin_versions()` tibble (subset of rows), or
#'   `NULL` for none.
#' @param side `"drive"` or `"local"`.
#' @param action Character vector, recycled to `nrow(versions)`.
#' @return A prune plan tibble.
#' @keywords internal
.prune_plan_rows <- function(name, versions, side, action) {
  n <- if (is.null(versions)) 0L else nrow(versions)
  if (n == 0L) return(.empty_prune_plan())
  hash <- if (is.null(versions$hash)) NA_character_ else as.character(versions$hash)
  tibble::tibble(
    name    = rep(name, n),
    version = as.character(versions$version),
    side    = rep(side, n),
    hash    = rep_len(hash, n),
    action  = rep_len(action, n)
  )
}

#' List a pin's versions on a sub-board, or `NULL` when it is not there
#'
#' @param sub_board A `pins` board or `NULL`.
#' @param name Pin name.
#' @return A `pins::pin_versions()` tibble, or `NULL`.
#' @keywords internal
.pin_versions_if_exists <- function(sub_board, name) {
  if (is.null(sub_board) || !pins::pin_exists(sub_board, name)) return(NULL)
  pins::pin_versions(sub_board, name)
}

#' Rows of a versions tibble beyond the newest `keep`
#'
#' `pins::pin_versions()` returns rows oldest first, newest last. We keep the
#' last `keep` rows and return the rest.
#'
#' @param versions A `pins::pin_versions()` tibble or `NULL`.
#' @param keep Integer. Number of newest versions to keep.
#' @return A tibble (possibly 0 rows) or `NULL`.
#' @keywords internal
.versions_beyond_keep <- function(versions, keep) {
  if (is.null(versions)) return(NULL)
  n <- nrow(versions)
  if (n <= keep) return(versions[0L, , drop = FALSE])
  versions[seq_len(n - keep), , drop = FALSE]
}

#' Plan which local versions to remove and which to keep unsynced
#'
#' Local versions beyond the newest `keep` are candidates. A candidate is
#' planned for removal only when its content hash is also among the Drive
#' versions (listed before any trashing), so the content survives on Drive.
#' A candidate whose hash is absent from Drive, or unparseable (`NA`), is a
#' version that was never synced: it is kept and marked `"keep_unsynced"`.
#' On an offline board Drive cannot be checked, so every candidate is kept.
#' A board that is `local_only` by construction (no Drive, not offline) has
#' nothing to sync to: every candidate is removed.
#'
#' Matching uses the 5-character hash prefix pins puts in version ids. Two
#' different contents share a prefix with probability about 1 in 16^5; that
#' risk is accepted.
#'
#' @param local_versions A `pins::pin_versions()` tibble of the local copy, or
#'   `NULL` when the pin is not there.
#' @param drive_versions A `pins::pin_versions()` tibble of Drive, or `NULL`.
#' @param name Pin name.
#' @param keep Integer. Number of newest versions to keep.
#' @param mode One of `"drive"` (board has a Drive board), `"offline"` or
#'   `"local_only"`.
#' @return A prune plan tibble with `side = "local"`.
#' @keywords internal
.local_versions_to_remove <- function(local_versions, drive_versions, name,
                                      keep, mode) {
  cand <- .versions_beyond_keep(local_versions, keep)
  if (is.null(cand) || nrow(cand) == 0L) return(.empty_prune_plan())

  hash <- if (is.null(cand$hash)) rep(NA_character_, nrow(cand)) else as.character(cand$hash)
  synced <- switch(mode,
    local_only = rep(TRUE, nrow(cand)),
    offline    = rep(FALSE, nrow(cand)),
    drive      = {
      drive_hash <- if (is.null(drive_versions$hash)) character() else
        as.character(drive_versions$hash)
      drive_hash <- drive_hash[!is.na(drive_hash)]
      !is.na(hash) & hash %in% drive_hash
    }
  )
  .prune_plan_rows(name, cand, "local", ifelse(synced, "remove", "keep_unsynced"))
}

#' Compute the prune plan for one pin
#'
#' @param board A `gdpins_board` object.
#' @param name Pin name.
#' @param keep Integer. Number of newest versions to keep.
#' @return A list with `plan` (prune plan tibble) and `present` (named integer
#'   vector of version counts per side that holds the pin).
#' @keywords internal
.prune_plan <- function(board, name, keep) {
  offline <- !is.null(attr(board, .GDPINS_OFFLINE_STATE_ATTR, exact = TRUE))
  mode <- if (offline) {
    "offline"
  } else if (is.null(board$drive_board)) {
    "local_only"
  } else {
    "drive"
  }

  # Drive is listed once, before any trashing; listing errors propagate.
  drive_v <- .pin_versions_if_exists(board$drive_board, name)
  local_v <- .pin_versions_if_exists(board$local_board, name)
  if (is.null(drive_v) && is.null(local_v)) {
    # Neither side holds the pin: let pins raise its usual "pin missing" error.
    pins::pin_versions(.prune_primary_board(board), name)
  }

  drive_plan <- .prune_plan_rows(
    name, .versions_beyond_keep(drive_v, keep), "drive", "remove"
  )
  local_plan <- .local_versions_to_remove(local_v, drive_v, name, keep, mode)

  present <- c(
    drive = if (is.null(drive_v)) NA_integer_ else nrow(drive_v),
    local = if (is.null(local_v)) NA_integer_ else nrow(local_v)
  )
  list(
    plan    = dplyr::bind_rows(.empty_prune_plan(), drive_plan, local_plan),
    present = present[!is.na(present)]
  )
}

#' Number of removals a plan counts against the threshold
#'
#' A synced version is removed on both sides but counts once: the larger of
#' the Drive and local removal counts.
#'
#' @param plan A prune plan tibble.
#' @return Integer scalar.
#' @keywords internal
.prune_n_remove <- function(plan) {
  rm <- plan$action == "remove"
  max(sum(rm & plan$side == "drive"), sum(rm & plan$side == "local"))
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

#' Remove one version directory from a local board
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

#' Report a prune plan and carry it out
#'
#' Shared by [gdpins_prune_pin_versions()] and [gdpins_prune_board_versions()]
#' after the threshold check.
#'
#' @param board A `gdpins_board` object.
#' @param name Pin name.
#' @param keep Integer. Number of newest versions to keep.
#' @param planned A `.prune_plan()` result.
#' @param dry_run Logical. Report only.
#' @return The prune plan tibble.
#' @keywords internal
.prune_report_and_apply <- function(board, name, keep, planned, dry_run) {
  plan     <- planned$plan
  rm       <- plan$action == "remove"
  drive_rm <- plan$version[rm & plan$side == "drive"]
  local_rm <- plan$version[rm & plan$side == "local"]
  unsynced <- plan$version[plan$action == "keep_unsynced"]
  n_drive  <- length(drive_rm)
  n_local  <- length(local_rm)
  n_kept   <- length(unsynced)

  kept_msg <- if (n_kept > 0L) {
    c(i = cli::format_inline(
      "Kept {n_kept} older local version{?s} not on Drive: {.val {unsynced}}."
    ))
  }

  if (n_drive + n_local == 0L) {
    present <- planned$present
    present_txt <- if (length(present) == 2L) {
      cli::format_inline(
        "{present[['drive']]} present on Drive, {present[['local']]} locally"
      )
    } else {
      cli::format_inline("{present[[1L]]} present")
    }
    cli::cli_inform(c(
      i = "No versions to remove for pin {.val {name}} (keep = {keep}, {present_txt}).",
      kept_msg
    ))
    return(plan)
  }

  if (dry_run) {
    cli::cli_inform(c(
      i = paste0(
        "DRY RUN -- pin {.val {name}}: would trash {n_drive} Drive version{?s} ",
        "and delete {n_local} local version{?s}."
      ),
      if (n_drive > 0L) c(" " = cli::format_inline("Drive: {.val {drive_rm}}")),
      if (n_local > 0L) c(" " = cli::format_inline("Local: {.val {local_rm}}")),
      kept_msg
    ))
    return(plan)
  }

  # Drive versions are trashed (recoverable -- NEVER hard-delete).
  for (v in drive_rm) {
    .trash_drive_version(board$adapter, board$drive_path, name, v)
  }
  # Local versions are deleted only when their content is on Drive (or the
  # board is local_only by construction); see .local_versions_to_remove().
  for (v in local_rm) {
    .remove_local_version(board$local_board$path, name, v)
  }

  cli::cli_inform(c(
    v = paste0(
      "Pruned pin {.val {name}}: trashed {n_drive} Drive version{?s}, ",
      "deleted {n_local} local version{?s}."
    ),
    kept_msg
  ))
  plan
}

# -- exported functions --------------------------------------------------------

#' Prune old versions of a single pin
#'
#' Removes old versions of one pin from Drive **and** the local copy (whichever
#' are present on `board`), keeping the `keep` most recent on each side. Drive
#' versions are always **trashed** (recoverable via `gd_trash()`), never
#' hard-deleted. Local-copy versions are deleted from the local filesystem.
#'
#' A local version beyond `keep` is deleted only when its content (matched by
#' the content hash in its version id) is also on Drive. A local version that
#' was never synced is kept and reported with action `"keep_unsynced"`. On an
#' offline board (see [gdpins_go_offline()]) Drive cannot be checked, so no
#' local version is deleted. A board that is `local_only` by construction has
#' no Drive to sync to: every version beyond `keep` is deleted.
#'
#' Defaults to `dry_run = TRUE` for safety: the plan is shown but nothing is
#' removed.
#'
#' Deleting more than `threshold` versions in a single call requires either
#' interactive confirmation or `force = TRUE`. The threshold check is skipped
#' during a dry run.
#'
#' **Raw files are never auto-deleted by any function** -- removal is manual
#' outside R.
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name. Must be a valid pin name; see the
#'   Pin names section of [verbs].
#' @param keep Integer scalar. Number of most-recent versions to keep on each
#'   side (Drive, local copy). Default `1`.
#' @param dry_run Logical. If `TRUE` (default), show the plan (Drive and local
#'   removals, and unsynced local versions that are kept) without removing
#'   anything.
#' @param threshold Integer scalar. Maximum number of versions to remove without
#'   requiring `force = TRUE` or interactive confirmation. Default `10`. The
#'   count is the larger of the Drive and the local removal counts, so a
#'   version removed from both sides counts once.
#' @param force Logical. If `TRUE`, skip the threshold check and its
#'   interactive confirmation. Default `FALSE`.
#'
#' @return Invisibly, the prune plan: a tibble with one row per version that
#'   was (or, in a dry run, would be) removed, or that was kept because it is
#'   not on Drive. Columns: `name` (pin name), `version` (version id), `side`
#'   (`"drive"` or `"local"`), `hash` (content-hash prefix from the version
#'   id) and `action` (`"remove"` or `"keep_unsynced"`). Zero rows when no
#'   version is beyond `keep`.
#' @seealso [gdpins_real_drive()], [gdpins_init_board()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' \dontrun{
#' gdpins_prune_pin_versions(board, name = "my-pin", keep = 3L)
#' }
#' @export
gdpins_prune_pin_versions <- function(
    board,
    name,
    keep      = 1,
    dry_run   = TRUE,
    threshold = 10,
    force     = FALSE
) {
  # -- input validation ------------------------------------------------------
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board} object.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  .check_pin_name(name)
  keep <- as.integer(keep)
  if (length(keep) != 1L || is.na(keep) || keep < 1L) {
    cli::cli_abort(c(
      "{.arg keep} must be a positive integer >= 1.",
      x = "Got {.val {keep}}."
    ))
  }

  planned  <- .prune_plan(board, name, keep)
  n_remove <- .prune_n_remove(planned$plan)

  # -- threshold guard (only for actual removals) ----------------------------
  if (!dry_run && n_remove > threshold && !force) {
    .prune_check_threshold(n_remove, threshold, paste0("pin '", name, "'"))
  }

  invisible(.prune_report_and_apply(board, name, keep, planned, dry_run))
}

#' Prune old versions of all pins in a board
#'
#' Applies [gdpins_prune_pin_versions()] to every pin in `board`. Defaults to
#' `dry_run = TRUE`. Pins are listed from Drive when the board has a Drive
#' board, otherwise from the local copy.
#'
#' @param board A `gdpins_board` object.
#' @param keep Integer scalar. Versions to keep per pin and side. Default `1`.
#' @param dry_run Logical. Show plan without removing. Default `TRUE`.
#' @param threshold Integer scalar. Maximum total number of versions to remove
#'   across all pins without `force = TRUE` or interactive confirmation.
#'   Default `10`. Each pin counts the larger of its Drive and local removal
#'   counts.
#' @param force Logical. Skip the threshold check and its interactive
#'   confirmation. Default `FALSE`.
#'
#' @return Invisibly, one prune plan tibble holding the rows of every pin (see
#'   [gdpins_prune_pin_versions()] for the columns). Zero rows when the board
#'   has no pins or nothing is beyond `keep`.
#' @seealso [gdpins_real_drive()], [gdpins_init_board()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_prune_board_versions(board, keep = 2L, dry_run = TRUE)
#' @export
gdpins_prune_board_versions <- function(
    board,
    keep      = 1,
    dry_run   = TRUE,
    threshold = 10,
    force     = FALSE
) {
  # -- input validation ------------------------------------------------------
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

  # -- enumerate pins --------------------------------------------------------
  primary  <- .prune_primary_board(board)
  all_pins <- pins::pin_list(primary)
  all_pins <- .drop_invalid_names(all_pins, .check_pin_name, "pin name")

  if (length(all_pins) == 0L) {
    cli::cli_inform(c(i = "No pins found in board {.val {board$name}}."))
    return(invisible(.empty_prune_plan()))
  }

  # -- plan every pin up front -----------------------------------------------
  plans <- lapply(all_pins, function(nm) .prune_plan(board, nm, keep))

  # -- pre-flight threshold check on the board total (actual removal only) ---
  if (!dry_run && !force) {
    total <- sum(vapply(plans, function(p) .prune_n_remove(p$plan), integer(1L)))
    if (total > threshold) {
      context <- cli::format_inline(
        "board '{board$name}' ({length(all_pins)} pin{?s}, {total} total removal{?s})"
      )
      .prune_check_threshold(total, threshold, context)
    }
  }

  # -- report and prune each pin (threshold already cleared above) ----------
  result <- lapply(seq_along(all_pins), function(i) {
    .prune_report_and_apply(board, all_pins[[i]], keep, plans[[i]], dry_run)
  })

  invisible(dplyr::bind_rows(.empty_prune_plan(), result))
}
