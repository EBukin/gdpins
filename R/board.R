#' Board initialisation and S3 methods for gdpins_board
#'
#' Provides [gdpins_init_board()] (the universal board constructor) and S3
#' methods for [print()], [summary()], and [format()] on `gdpins_board`
#' objects.
#'
#' @name board
NULL

# ── Legal on_discrepancy values ───────────────────────────────────────────────

.ON_DISCREPANCY_VALUES <- c(
  "prompt", "warn", "sync_from_drive", "sync_to_drive", "ignore"
)

# ── Internal helpers ──────────────────────────────────────────────────────────

#' @keywords internal
.board_readline <- function(prompt) readline(prompt)

#' Resolve the default on_discrepancy value
#' @keywords internal
.resolve_on_discrepancy <- function(on_discrepancy) {
  if (is.null(on_discrepancy)) {
    return(if (rlang::is_interactive()) "prompt" else "warn")
  }
  on_discrepancy <- match.arg(on_discrepancy, .ON_DISCREPANCY_VALUES)
  on_discrepancy
}

#' Handle init-time (or reconnect-time) sync check
#'
#' Calls `gdpins_board_status()` on `x` and acts per `on_discrepancy`. Errors
#' from `gdpins_board_status` (e.g. WS5 stub) are caught and treated as
#' offline/unavailable — a warning is emitted and `x` is returned as-is.
#'
#' Shared by [gdpins_init_board()]/[gdpins_raw_connect()] (init-time) and
#' [gdpins_go_online()] (reconnect-time) — `x` may be a `gdpins_board` or a
#' `gdpins_raw_conn`, since `gdpins_board_status()`/`gdpins_sync()` dispatch on
#' both.
#'
#' @param x A `gdpins_board` or `gdpins_raw_conn` object.
#' @param on_discrepancy Resolved on_discrepancy value (never `NULL`).
#' @param label Character scalar used in messages. Defaults to `x$name` (set
#'   on `gdpins_board`) or `"connection"` when unavailable (e.g. raw
#'   connections, which have no `name` field).
#'
#' @keywords internal
.handle_init_sync <- function(x, on_discrepancy, label = NULL) {
  if (is.null(label)) {
    label <- if (!is.null(x$name)) x$name else "connection"
  }

  status <- tryCatch(
    gdpins_board_status(x),
    error = function(e) {
      cli::cli_warn(c(
        "!" = "gdpins_board_status() failed during sync check.",
        "i" = "Sync status unavailable; proceeding without sync check.",
        "i" = "Detail: {conditionMessage(e)}"
      ))
      NULL
    }
  )

  if (is.null(status)) {
    return(invisible(x))
  }

  switch(on_discrepancy,
    ignore = {
      # Do nothing
    },
    warn = {
      cli::cli_warn(c(
        "!" = paste0(
          "{.val {label}}: sync discrepancy detected between ",
          "Drive and local. Run {.fn gdpins_sync} to reconcile."
        )
      ))
    },
    prompt = {
      if (rlang::is_interactive()) {
        cli::cli_inform(c(
          "!" = paste0(
            "{.val {label}}: sync discrepancy detected. ",
            "Run {.fn gdpins_sync} to reconcile."
          )
        ))
      } else {
        cli::cli_warn(c(
          "!" = paste0(
            "{.val {label}}: sync discrepancy detected between ",
            "Drive and local."
          )
        ))
      }
    },
    sync_from_drive = {
      cli::cli_inform(
        "Syncing {.val {label}} from Drive (on_discrepancy = \\
        {.val sync_from_drive})."
      )
      tryCatch(
        gdpins_sync(x, direction = "from_drive"),
        error = function(e) {
          cli::cli_warn("Sync from Drive failed: {conditionMessage(e)}")
        }
      )
    },
    sync_to_drive = {
      cli::cli_inform(
        "Syncing {.val {label}} to Drive (on_discrepancy = \\
        {.val sync_to_drive})."
      )
      tryCatch(
        gdpins_sync(x, direction = "to_drive"),
        error = function(e) {
          cli::cli_warn("Sync to Drive failed: {conditionMessage(e)}")
        }
      )
    }
  )

  invisible(x)
}

# ── Exported constructor ──────────────────────────────────────────────────────

#' Initialise a gdpins board
#'
#' Builds a board in one of three legal configurations depending on the
#' combination of arguments supplied:
#'
#' - **`"local_only"`** — `local_dir` provided, no `drive_path`/`adapter`.
#' - **`"drive_cache"`** — `drive_path` + `adapter` + `cache_dir`, no
#'   `local_dir`.
#' - **`"drive_cache_local"`** — all three: `drive_path`, `cache_dir`, and
#'   `local_dir`.
#'
#' On init the board checks for sync discrepancies between Drive and local
#' (governed by `on_discrepancy`). Non-existent Drive boards are never
#' auto-created unless `create = TRUE`.
#'
#' @param name Character scalar. Board/layer label (e.g. `"data_raw"`).
#' @param drive_path Character scalar. Drive path for the board (relative to
#'   the adapter root), or `NULL` for `"local_only"`.
#' @param cache_dir Character scalar. Local cache directory path, or `NULL`.
#' @param local_dir Character scalar. Standalone local board directory path, or
#'   `NULL`.
#' @param versioned Logical. Whether the board stores pin versions. Default
#'   `TRUE`.
#' @param create Logical or `NA`. `TRUE` = create Drive board if absent;
#'   `FALSE` = error if absent; `NA` (default) = interactive CLI prompt or
#'   error.
#' @param on_discrepancy Character scalar or `NULL`. One of
#'   `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`. `NULL`
#'   resolves to `"prompt"` interactively or `"warn"` non-interactively.
#' @param adapter A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.
#'
#' @return A `gdpins_board` object.
#' @seealso [gdpins_real_drive()] to create an adapter, [gdpins_go_offline()]
#'   to temporarily detach an existing board from Drive and work locally.
#' @examples
#' # --- Fake adapter (no network) ---
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' board
#'
#' # --- Real adapter (requires Google Drive auth) ---
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = "~/.cache/gdpins/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#'
#' # Supply a Drive folder ID directly as drive_path
#' board2 <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
#'   cache_dir  = "~/.cache/gdpins/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' }
#' @export
gdpins_init_board <- function(
    name,
    drive_path      = NULL,
    cache_dir       = NULL,
    local_dir       = NULL,
    versioned       = TRUE,
    create          = NA,
    on_discrepancy  = NULL,
    adapter         = NULL
) {
  # ── Validate name ────────────────────────────────────────────────────────────
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  # ── Validate versioned ───────────────────────────────────────────────────────
  if (!is.logical(versioned) || length(versioned) != 1L || is.na(versioned)) {
    cli::cli_abort("{.arg versioned} must be a non-NA logical scalar.")
  }

  # ── Validate on_discrepancy ──────────────────────────────────────────────────
  on_discrepancy <- .resolve_on_discrepancy(on_discrepancy)

  # ── Determine config ─────────────────────────────────────────────────────────
  has_drive <- !is.null(drive_path)
  has_cache <- !is.null(cache_dir)
  has_local <- !is.null(local_dir)
  has_adapter <- !is.null(adapter)

  if (!has_drive && !has_local) {
    cli::cli_abort(c(
      "Cannot determine board configuration.",
      x = "At least one of {.arg drive_path} or {.arg local_dir} must be supplied.",
      i = paste0(
        "Use {.arg local_dir} alone for local-only, or supply ",
        "{.arg drive_path} + {.arg cache_dir} + {.arg adapter} for Drive."
      )
    ))
  }

  if (has_drive && !has_adapter) {
    cli::cli_abort(c(
      "{.arg adapter} is required when {.arg drive_path} is supplied.",
      i = "Pass a {.cls gdpins_drive_adapter} created by {.fn gdpins_fake_drive} or {.fn gdpins_real_drive}."
    ))
  }

  if (has_drive && !has_cache) {
    cli::cli_abort(c(
      "{.arg cache_dir} is required when {.arg drive_path} is supplied.",
      i = "Provide a local directory path for the Drive cache."
    ))
  }

  config <- if (!has_drive && has_local) {
    "local_only"
  } else if (has_drive && !has_local) {
    "drive_cache"
  } else {
    "drive_cache_local"
  }

  # ── local_only ───────────────────────────────────────────────────────────────
  if (config == "local_only") {
    if (!dir.exists(local_dir)) {
      fs::dir_create(local_dir)
    }
    local_board <- pins::board_folder(local_dir, versioned = versioned)
    board <- new_gdpins_board(
      config      = "local_only",
      name        = name,
      local_board = local_board,
      local_dir   = local_dir,
      versioned   = versioned
    )
    .handle_init_sync(board, on_discrepancy)
    return(board)
  }

  # ── Drive configs (drive_cache / drive_cache_local) ───────────────────────────

  # Offline check — if offline and Drive is needed, fall back to local-only
  # if a local_dir is available, otherwise error
  is_online <- tryCatch(gdpins_is_online(), error = function(e) FALSE)

  if (!is_online) {
    cli::cli_warn(c(
      "!" = "No internet connection detected.",
      "i" = paste0(
        "Drive board {.val {drive_path}} is unavailable offline. ",
        "Falling back to local-only mode."
      )
    ))

    if (config == "drive_cache_local" && has_local) {
      if (!dir.exists(local_dir)) fs::dir_create(local_dir)
      local_board <- pins::board_folder(local_dir, versioned = versioned)
      board <- new_gdpins_board(
        config      = "local_only",
        name        = name,
        local_board = local_board,
        local_dir   = local_dir,
        versioned   = versioned
      )
    } else {
      # drive_cache with no local_dir — fall back to cache as local
      if (!dir.exists(cache_dir)) fs::dir_create(cache_dir)
      local_board <- pins::board_folder(cache_dir, versioned = versioned)
      board <- new_gdpins_board(
        config      = "local_only",
        name        = name,
        local_board = local_board,
        local_dir   = cache_dir,
        versioned   = versioned
      )
    }
    .handle_init_sync(board, on_discrepancy)
    return(board)
  }

  # ── create-confirm logic ─────────────────────────────────────────────────────
  drive_exists <- gd_exists(adapter, drive_path)

  # ── Drive ID fast-path (real adapter only) ────────────────────────────────
  # If drive_path looks like a Drive folder ID and does not already resolve
  # relative to the adapter root, verify directly.
  if (!drive_exists && identical(adapter$kind, "real") && .is_drive_id(drive_path)) {
    # nocov start
    d <- tryCatch(
      googledrive::drive_get(googledrive::as_id(drive_path)),
      error = function(e) NULL
    )
    if (is.null(d) || nrow(d) == 0L) {
      cli::cli_abort(c(
        "Drive folder ID not found: {.val {drive_path}}",
        x = "Folder does not exist or is not accessible.",
        i = "Verify the ID in your Google Drive URL."
      ))
    }
    drive_folder_id <- drive_path
    if (!dir.exists(cache_dir)) fs::dir_create(cache_dir)
    drive_board <- pins::board_gdrive(
      googledrive::as_id(drive_folder_id),
      cache = cache_dir
    )
    cache_board <- pins::board_folder(cache_dir, versioned = versioned)
    if (config == "drive_cache") {
      board <- new_gdpins_board(
        config      = "drive_cache",
        name        = name,
        drive_board = drive_board,
        cache_board = cache_board,
        cache_dir   = cache_dir,
        drive_path  = drive_path,
        adapter     = adapter,
        versioned   = versioned
      )
      .handle_init_sync(board, on_discrepancy)
      return(board)
    }
    if (!dir.exists(local_dir)) fs::dir_create(local_dir)
    local_board <- pins::board_folder(local_dir, versioned = versioned)
    board <- new_gdpins_board(
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
    .handle_init_sync(board, on_discrepancy)
    return(board)
    # nocov end
  }

  if (!drive_exists) {
    if (isTRUE(create)) {
      gd_mkdir(adapter, drive_path)
    } else if (isFALSE(create)) {
      cli::cli_abort(c(
        "Drive board path does not exist: {.path {drive_path}}",
        x = "{.arg create} is {.val FALSE}; refusing to create.",
        i = "Pass {.code create = TRUE} to create automatically."
      ))
    } else {
      # create = NA: prompt if interactive, error if not
      if (rlang::is_interactive()) {
        answer_raw <- .board_readline(
          paste0(
            "Drive path '", drive_path,
            "' does not exist. Create it? [y/N] "
          )
        )
        answer <- tolower(trimws(answer_raw))
        if (answer %in% c("y", "yes")) {
          gd_mkdir(adapter, drive_path)
        } else {
          cli::cli_abort(c(
            "Drive board path does not exist: {.path {drive_path}}",
            i = "Pass {.code create = TRUE} to create automatically."
          ))
        }
      } else {
        cli::cli_abort(c(
          "Drive board path does not exist: {.path {drive_path}}",
          x = "Non-interactive session: cannot prompt.",
          i = "Pass {.code create = TRUE} to create automatically."
        ))
      }
    }
  }

  # ── Build drive_board ────────────────────────────────────────────────────────
  # Fake adapter: board_folder over <fake_root>/<drive_path>
  # Real adapter: pins::board_gdrive(drive_path, cache = cache_dir)
  if (!dir.exists(cache_dir)) {
    fs::dir_create(cache_dir)
  }

  if (identical(adapter$kind, "fake")) {
    drive_board_dir <- file.path(
      adapter$root,
      gsub("/", .Platform$file.sep, drive_path, fixed = TRUE)
    )
    if (!dir.exists(drive_board_dir)) {
      fs::dir_create(drive_board_dir)
    }
    drive_board <- pins::board_folder(drive_board_dir, versioned = versioned)
  } else {
    # Resolve the subfolder's Drive ID so board_gdrive is anchored inside the
    # adapter's root folder rather than searching from My Drive root.
    drive_folder_id <- adapter$get_id(drive_path)
    drive_board <- pins::board_gdrive(
      googledrive::as_id(drive_folder_id),
      cache = cache_dir
    )
  }

  cache_board <- pins::board_folder(cache_dir, versioned = versioned)

  # ── drive_cache ───────────────────────────────────────────────────────────────
  if (config == "drive_cache") {
    board <- new_gdpins_board(
      config      = "drive_cache",
      name        = name,
      drive_board = drive_board,
      cache_board = cache_board,
      cache_dir   = cache_dir,
      drive_path  = drive_path,
      adapter     = adapter,
      versioned   = versioned
    )
    .handle_init_sync(board, on_discrepancy)
    return(board)
  }

  # ── drive_cache_local ────────────────────────────────────────────────────────
  if (!dir.exists(local_dir)) {
    fs::dir_create(local_dir)
  }
  local_board <- pins::board_folder(local_dir, versioned = versioned)

  board <- new_gdpins_board(
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
  .handle_init_sync(board, on_discrepancy)
  board
}

# ── S3 print / format / summary ───────────────────────────────────────────────

#' Format a gdpins_board as a compact one-line string (≤80 cols)
#'
#' @param x A `gdpins_board` object.
#' @param ... Unused.
#'
#' @return Character scalar.
#' @export
#' @exportS3Method format gdpins_board
format.gdpins_board <- function(x, ...) {
  # Components indicator: D=drive, C=cache, L=local
  comps <- paste0(
    if (!is.null(x$drive_board)) "D" else "-",
    if (!is.null(x$cache_board)) "C" else "-",
    if (!is.null(x$local_board)) "L" else "-"
  )
  ver <- if (isTRUE(x$versioned)) "v+" else "v-"
  cfg <- x$config

  # Build a compact single line
  path_str <- if (!is.null(x$drive_path)) {
    dp <- x$drive_path
    if (nchar(dp) > 20L) dp <- paste0("...", substr(dp, nchar(dp) - 16L, nchar(dp)))
    dp
  } else if (!is.null(x$local_dir)) {
    ld <- x$local_dir
    if (nchar(ld) > 20L) ld <- paste0("...", substr(ld, nchar(ld) - 16L, nchar(ld)))
    ld
  } else {
    ""
  }

  line <- paste0(
    "<gdpins_board> [", comps, "] ", ver,
    " cfg=", cfg,
    " name=", x$name,
    if (nzchar(path_str)) paste0(" path=", path_str) else ""
  )

  # Hard truncate at 80 chars
  if (nchar(line) > 80L) {
    line <- paste0(substr(line, 1L, 77L), "...")
  }
  line
}

#' Print a gdpins_board object (compact, ≤80 cols)
#'
#' @param x A `gdpins_board` object.
#' @param ... Unused.
#'
#' @return Invisibly `x`.
#' @export
#' @exportS3Method print gdpins_board
print.gdpins_board <- function(x, ...) {
  cli::cli_text(format(x, ...))
  gd_cli_kv(
    config    = x$config,
    name      = x$name,
    versioned = as.character(x$versioned)
  )
  if (!is.null(x$drive_path)) {
    gd_cli_kv(drive = x$drive_path)
  }
  if (!is.null(x$cache_dir)) {
    gd_cli_kv(cache = x$cache_dir)
  }
  if (!is.null(x$local_dir)) {
    gd_cli_kv(local = x$local_dir)
  }
  invisible(x)
}

#' Summarise a gdpins_board object
#'
#' Prints a compact summary (one row per board component) to the console.
#'
#' @param object A `gdpins_board` object.
#' @param ... Unused.
#'
#' @return Invisibly `object`.
#' @export
#' @exportS3Method summary gdpins_board
summary.gdpins_board <- function(object, ...) {
  cli::cli_text("<gdpins_board> summary")
  gd_cli_kv(
    name      = object$name,
    config    = object$config,
    versioned = as.character(object$versioned)
  )
  if (!is.null(object$drive_path)) {
    gd_cli_kv(drive_path = object$drive_path)
  }
  if (!is.null(object$cache_dir)) {
    gd_cli_kv(cache_dir = object$cache_dir)
  }
  if (!is.null(object$local_dir)) {
    gd_cli_kv(local_dir = object$local_dir)
  }
  # Component status
  comps <- c(
    if (!is.null(object$drive_board)) "drive_board" else NULL,
    if (!is.null(object$cache_board)) "cache_board" else NULL,
    if (!is.null(object$local_board)) "local_board" else NULL
  )
  gd_cli_kv(components = paste(comps, collapse = ", "))
  invisible(object)
}
