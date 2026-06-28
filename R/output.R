#' Output rendering and Drive publishing
#'
#' Functions for saving figures (PNG/SVG only — ggplot objects are **not**
#' stored) and publishing local output to Google Drive as a deliberate final
#' step.
#'
#' @name output
NULL

#' Save a ggplot figure to disk
#'
#' Renders a ggplot object to a PNG or SVG file in `dir`. The ggplot object
#' itself is never stored in a pin. File name is `<name>.<device>`.
#'
#' @param plot A `ggplot` object.
#' @param name Character scalar. Base file name (without extension).
#' @param dir Character scalar. Output directory path.
#' @param width Numeric scalar. Figure width in inches. Default `7`.
#' @param height Numeric scalar. Figure height in inches. Default `5`.
#' @param dpi Integer scalar. Resolution in DPI. Default `300`.
#' @param device Character scalar. One of `c("png", "svg")`. Default `"png"`.
#'
#' @return Invisibly, the path to the saved file.
#' @export
gdpins_save_figure <- function(
    plot,
    name,
    dir,
    width  = 7,
    height = 5,
    dpi    = 300,
    device = c("png", "svg")
) {
  rlang::check_installed("ggplot2", reason = "to render figures")
  device <- match.arg(device)

  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort(c(
      "{.arg name} must be a non-empty character scalar.",
      x = "Got {.cls {class(name)}} of length {length(name)}."
    ))
  }
  if (!is.character(dir) || length(dir) != 1L || !nzchar(dir)) {
    cli::cli_abort(c(
      "{.arg dir} must be a non-empty character scalar.",
      x = "Got {.cls {class(dir)}} of length {length(dir)}."
    ))
  }

  fs::dir_create(dir)
  out_path <- file.path(dir, paste0(name, ".", device))

  ggplot2::ggsave(
    filename = out_path,
    plot     = plot,
    width    = width,
    height   = height,
    dpi      = dpi,
    device   = device
  )

  invisible(out_path)
}

#' Publish local output to Google Drive
#'
#' Copies local output (tables board and/or figures directory) to their
#' corresponding Drive destinations. This is a deliberate, user-triggered
#' action — local output is never auto-published.
#'
#' `dry_run = TRUE` prints what would be published without uploading anything.
#' Blocked when offline.
#'
#' @param tables_board A `gdpins_board` or `NULL`. Source board for output
#'   tables. The read-authoritative local pins board inside `tables_board` is
#'   mirrored to Drive (local-first: local > cache > drive board).
#' @param figures_dir Character scalar or `NULL`. Local directory containing
#'   PNG/SVG figures to publish.
#' @param drive_tables Character scalar. Drive destination folder name for
#'   tables. Default `"output-tables"`.
#' @param drive_figures Character scalar. Drive destination folder name for
#'   figures. Default `"output-figures"`.
#' @param adapter A `gdpins_drive_adapter` or `NULL`. If `NULL`, uses the
#'   adapter from `tables_board`.
#' @param dry_run Logical. If `TRUE`, show what would be published without
#'   uploading. Default `FALSE`.
#'
#' @return Invisibly `NULL`. Called for its side effect.
#' @seealso [gdpins_real_drive()] to create an adapter.
#' @examples
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#'
#' # Publish via adapter directly
#' gdpins_publish_output(
#'   figures_dir   = "output/figures",
#'   adapter       = adapter,
#'   drive_figures = "my-project/output-figures"
#' )
#'
#' # Or pass a board that already holds the adapter
#' board <- gdpins_init_board(
#'   name       = "output",
#'   drive_path = "my-project/output-tables",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_publish_output(tables_board = board, figures_dir = "output/figures")
#' }
#' @export
gdpins_publish_output <- function(
    tables_board  = NULL,
    figures_dir   = NULL,
    drive_tables  = "output-tables",
    drive_figures = "output-figures",
    adapter       = NULL,
    dry_run       = FALSE
) {
  # ── Resolve adapter ────────────────────────────────────────────────────────
  if (is.null(adapter) && !is.null(tables_board)) {
    adapter <- tables_board$adapter
  }

  if (is.null(adapter)) {
    cli::cli_abort(c(
      "An adapter is required for publishing to Drive.",
      i = paste0(
        "Supply {.arg adapter} directly or pass a {.arg tables_board} ",
        "that has one."
      )
    ))
  }

  # ── Offline guard ──────────────────────────────────────────────────────────
  if (!gdpins_is_online()) {
    cli::cli_abort(c(
      "Publishing to Drive requires an internet connection.",
      x = "No connection detected.",
      i = "Connect to the internet and retry."
    ))
  }

  # ── Collect work items ────────────────────────────────────────────────────
  tables_work  <- .collect_tables_work(tables_board)
  figures_work <- .collect_figures_work(figures_dir)

  total <- nrow(tables_work) + nrow(figures_work)

  if (total == 0L) {
    cli::cli_inform("Nothing to publish.")
    return(invisible(NULL))
  }

  # ── Dry-run: report and exit ──────────────────────────────────────────────
  if (dry_run) {
    cli::cli_inform(c("i" = "Dry-run: {total} item{?s} would be published."))
    if (nrow(tables_work) > 0L) {
      cli::cli_inform(
        c("i" = "Tables ({nrow(tables_work)}): {.val {tables_work$pin_name}}")
      )
    }
    if (nrow(figures_work) > 0L) {
      cli::cli_inform(
        c(
          "i" = paste0(
            "Figures ({nrow(figures_work)}): ",
            "{.val {figures_work$file_name}}"
          )
        )
      )
    }
    return(invisible(NULL))
  }

  # ── Publish tables ────────────────────────────────────────────────────────
  if (nrow(tables_work) > 0L) {
    gd_mkdir(adapter, drive_tables)
    src_board <- .resolve_read_board(tables_board)
    purrr::walk(tables_work$pin_name, function(pin_nm) {
      obj <- pins::pin_read(src_board, pin_nm)
      tmp <- tempfile(fileext = ".rds")
      on.exit(unlink(tmp), add = TRUE)
      saveRDS(obj, tmp)
      drive_path <- paste0(drive_tables, "/", pin_nm, ".rds")
      gd_upload(adapter, tmp, drive_path)
    })
  }

  # ── Publish figures ───────────────────────────────────────────────────────
  if (nrow(figures_work) > 0L) {
    gd_mkdir(adapter, drive_figures)
    purrr::walk2(
      figures_work$local_path,
      figures_work$file_name,
      function(local_p, file_nm) {
        drive_path <- paste0(drive_figures, "/", file_nm)
        gd_upload(adapter, local_p, drive_path)
      }
    )
  }

  invisible(NULL)
}

# ── Internal helpers ──────────────────────────────────────────────────────────

#' Resolve the read-authoritative pins board from a gdpins_board
#'
#' Local-first: local_board > cache_board > drive_board.
#'
#' @param board A `gdpins_board`.
#' @return A `pins` board object.
#' @keywords internal
.resolve_read_board <- function(board) {
  if (!is.null(board$local_board)) return(board$local_board)
  if (!is.null(board$cache_board)) return(board$cache_board)
  board$drive_board
}

#' Collect table publish work items from a gdpins_board
#'
#' @param tables_board A `gdpins_board` or `NULL`.
#' @return A tibble with column `pin_name`.
#' @keywords internal
.collect_tables_work <- function(tables_board) {
  if (is.null(tables_board)) {
    return(tibble::tibble(pin_name = character()))
  }
  src <- .resolve_read_board(tables_board)
  tibble::tibble(pin_name = pins::pin_list(src))
}

#' Collect figure publish work items from a local figures directory
#'
#' @param figures_dir Character scalar or `NULL`.
#' @return A tibble with columns `local_path` and `file_name`.
#' @keywords internal
.collect_figures_work <- function(figures_dir) {
  if (is.null(figures_dir)) {
    return(tibble::tibble(local_path = character(), file_name = character()))
  }
  if (!nzchar(figures_dir)) {
    return(tibble::tibble(local_path = character(), file_name = character()))
  }
  if (!dir.exists(figures_dir)) {
    return(tibble::tibble(local_path = character(), file_name = character()))
  }
  files <- list.files(
    figures_dir,
    full.names  = TRUE,
    pattern     = "\\.(png|svg)$",
    ignore.case = TRUE
  )
  tibble::tibble(
    local_path = files,
    file_name  = basename(files)
  )
}
