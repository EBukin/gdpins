#' Raw-exogenous connection
#'
#' Plain-file interface for data as received from external APIs or sources.
#' No pins metadata layer — files are stored verbatim or serialised from R
#' objects. Drive path is the truth; a local directory mirrors it.
#'
#' @section Raw connection verbs:
#' | Verb | Takes | Returns |
#' | --- | --- | --- |
#' | [gdpins_raw_connect()] | `drive_path`, `local_path` | a `gdpins_raw_conn` |
#' | [gdpins_raw_put_object()] | an R object + a `name` | invisibly `NULL` |
#' | [gdpins_raw_put_file()] | a file `path` + a `name` | invisibly `NULL` |
#' | [gdpins_raw_get()] | a `name` | **the object** |
#' | [gdpins_raw_path()] | a `name` or Drive ID | **a path** |
#' | [gdpins_raw_ls()] | a `depth` | a listing tibble |
#' | [gdpins_raw_remove()] | a `name` | invisibly `NULL` |
#' | [gdpins_refresh_disconnect()] | — | invisibly `NULL` |
#'
#' @section Objects vs paths:
#' The governing rule across gdpins: **`*_get` / `*_read` return objects,
#' `*_path` returns paths.** The extension never switches the mode.
#'
#' [gdpins_raw_get()] deserialises, so it only accepts the four formats gdpins
#' knows how to read — `.rds`, `.parquet`, `.geojson`, `.csv`. Anything else is
#' an error naming those formats and pointing at [gdpins_raw_path()].
#'
#' [gdpins_raw_path()] returns a path for **any** extension, downloading from
#' Drive on demand. It is the escape hatch for formats gdpins does not read:
#' get the path, then hand it to whatever package does.
#'
#' [gdpins_raw_put_file()] mirrors that asymmetry. It uploads bytes verbatim, so
#' it accepts any extension (`.gpkg`, `.tif`, `.xlsx`, …) and only insists that
#' there *is* one.
#'
#' @section Name resolution:
#' [gdpins_raw_path()], [gdpins_raw_get()] and [gdpins_pin_read()] resolve the
#' name you pass against what actually exists, stopping at the first hit:
#'
#' 1. Exact relative path → resolve.
#' 2. Exact basename, unique → resolve silently (`"cars.csv"` finds
#'    `"sub/cars.csv"`).
#' 3. Exact basename, several matches → error listing every full path.
#' 4. Case-insensitive exact, unique → resolve silently.
#' 5. Same stem, different extension → error, suggesting it (`"cars.csv"` when
#'    only `"cars.parquet"` exists).
#' 6. Close on edit distance → error, suggesting the 5 nearest.
#' 7. Nothing close → error naming the connection, pointing at listing mode.
#'
#' Auto-resolve happens **only** at rungs 1, 2 and 4, where the match is both
#' exact and unique. Rungs 3 and 5–7 only ever suggest — they never guess.
#'
#' Rung 4 also settles a real platform difference: `file.exists()` is
#' case-insensitive on Windows and case-sensitive elsewhere, so gdpins does the
#' case-folding itself rather than letting the filesystem do it on one platform
#' and not the other.
#'
#' [gdpins_pin_read()] and [gdpins_pin_path()] use the same ladder without rungs
#' 2–3: pin names are flat, so "path" and "basename" are the same question.
#'
#' [gdpins_raw_remove()] uses **rung 1 only**. It hard-deletes the local copy, so
#' it never auto-resolves a near-miss onto a real file; a missing target stays an
#' idempotent no-op.
#'
#' @section Glob and listing mode:
#' A `name` containing `*` or `?` switches [gdpins_raw_path()],
#' [gdpins_raw_get()], [gdpins_raw_remove()], [gdpins_pin_read()] and
#' [gdpins_pin_path()] into **listing mode**: they return a listing of what
#' matches instead of acting on one item. Listing mode never bulk-reads and never
#' bulk-deletes.
#'
#' - `"*"` — everything.
#' - `"*.csv"` — every `.csv`, at **any depth** (unlike [gdpins_raw_ls()], whose
#'   `depth = 2` default hides `sub/sub/folder/file.rds`).
#'
#' Matching is case-sensitive on every platform, so `"*.csv"` does not match
#' `"CARS.CSV"`. Raw verbs return a `gdpins_raw_listing`; pin verbs return a
#' `gdpins_pin_listing`. Both are ordinary tibbles with a print method that shows
#' names only.
#'
#' @name raw-connection
NULL

# ── Legal values ──────────────────────────────────────────────────────────────

.ON_DISCREPANCY_VALUES <- c("prompt", "warn", "sync_from_drive",
                             "sync_to_drive", "ignore")

# ── Mockable shims (WS4-internal) ─────────────────────────────────────────────

# Thin wrappers around base functions.
# - GDPINS_RAW_INTERACTIVE env var overrides interactive() for testing.
# - GDPINS_RAW_READLINE    env var overrides readline() for testing.
.raw_is_interactive <- function() {
  override <- Sys.getenv("GDPINS_RAW_INTERACTIVE", unset = "")
  if (nzchar(override)) return(override == "TRUE")
  interactive()
}

.raw_readline <- function(prompt) {
  override <- Sys.getenv("GDPINS_RAW_READLINE", unset = "")
  if (nzchar(override)) return(override)
  readline(prompt)
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Resolve on_discrepancy to a concrete value (never NULL at runtime)
.resolve_on_discrepancy <- function(on_discrepancy) {
  if (!is.null(on_discrepancy)) {
    legal <- .ON_DISCREPANCY_VALUES
    if (!on_discrepancy %in% legal) {
      cli::cli_abort(c(
        "{.arg on_discrepancy} must be one of {.val {(legal)}}.",
        x = "Got {.val {on_discrepancy}}."
      ))
    }
    return(on_discrepancy)
  }
  if (.raw_is_interactive()) "prompt" else "warn"
}

# Derive the extension from a name (lowercase, with dot)
.raw_ext <- function(name) {
  ext <- tolower(tools::file_ext(name))
  if (!nzchar(ext)) return("")
  paste0(".", ext)
}

# The formats gdpins can serialise/deserialise as R objects.
.RAW_OBJECT_EXTS <- c(".rds", ".parquet", ".geojson", ".csv")

# Validate that extension is supported (abort on unknown)
.check_ext <- function(name) {
  ext <- .raw_ext(name)
  if (!ext %in% .RAW_OBJECT_EXTS) {
    # Local binding: cli >= 3.4 reads a leading dot inside {} as a style name.
    supported <- .RAW_OBJECT_EXTS
    cli::cli_abort(c(
      "Unsupported file extension {.val {ext}} in {.val {name}}.",
      i = "Supported extensions: {.val {supported}}."
    ))
  }
  ext
}

# As .check_ext(), but phrased for gdpins_raw_get(): an unreadable extension is
# not a dead end, it just means "this is a file, not an object" -- so point at
# gdpins_raw_path(), which returns a path for any extension.
.check_ext_get <- function(name) {
  ext <- .raw_ext(name)
  if (!ext %in% .RAW_OBJECT_EXTS) {
    # Local binding: cli >= 3.4 reads a leading dot inside {} as a style name.
    supported <- .RAW_OBJECT_EXTS
    shown     <- if (nzchar(ext)) ext else "<none>"
    cli::cli_abort(c(
      "Cannot read {.val {name}} as an R object.",
      x = "{.fn gdpins_raw_get} reads only {.val {supported}}; got {.val {shown}}.",
      i = "Use {.fn gdpins_raw_path} to get the file path instead, then read it
           with whatever package handles this format."
    ))
  }
  ext
}

# ── Listing class ─────────────────────────────────────────────────────────────

# Tag a raw listing tibble. The class goes *ahead* of the tibble classes so the
# print method takes precedence while every tibble/dplyr operation still works
# and `inherits(x, "tbl_df")` stays TRUE.
.new_raw_listing <- function(x) {
  class(x) <- unique(c("gdpins_raw_listing", class(x)))
  x
}

#' @export
print.gdpins_raw_listing <- function(x, ...) {
  n <- nrow(x)
  if (n == 0L) {
    cli::cli_alert_info("No matching files.")
    return(invisible(x))
  }
  cli::cli_text("{.strong {n} file{?s}}")
  # Names/paths only: a listing answers "what is there", not "what is in it".
  cli::cli_ul(gsub("}", "}}", gsub("{", "{{", x$name, fixed = TRUE), fixed = TRUE))
  invisible(x)
}

# ── Name resolution ───────────────────────────────────────────────────────────

# TRUE when `name` asks for a listing rather than one specific file.
.is_glob <- function(name) grepl("[*?]", name)

# Does `name` exist locally, spelled exactly as given?
#
# file.exists() is case-insensitive on Windows and case-sensitive elsewhere, so
# a plain file.exists() fast path would answer TRUE for "CARS.CSV" on Windows
# and return a path spelled differently from the file on disk -- while Linux
# fell through to rung 4 and returned the real spelling. Comparing against the
# actual directory entries is case-exact on every platform, so rung 4 does the
# case-folding uniformly instead of the filesystem doing it on one platform.
# Every component must match case-exactly, not just the basename: dirname() is
# resolved by the filesystem too, so "SUB/cars.csv" would otherwise pass rung 1
# on Windows and return a path spelled unlike the directory on disk.
.local_exists_exact <- function(conn, name) {
  if (!file.exists(.local_full_path(conn, name))) return(FALSE)
  parts <- strsplit(name, "[/\\\\]")[[1L]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0L) return(FALSE)
  # Walk down from the root, listing one directory per component -- cheaper than
  # a recursive listing, and only ever reached when file.exists() already hit.
  dir <- conn$local_path
  for (part in parts) {
    if (!part %in% list.files(dir, all.files = TRUE, no.. = TRUE)) return(FALSE)
    dir <- file.path(dir, part)
  }
  TRUE
}

# Every file in the connection, full depth, as relative "/"-separated paths.
# Drive is the truth and the local directory mirrors it, so gdpins_raw_ls()
# reports the Drive side whenever an adapter is attached. depth = Inf because
# the default depth = 2 hides sub/sub/folder/file.rds.
.raw_file_candidates <- function(conn) {
  listing <- gdpins_raw_ls(conn, depth = Inf)
  if (nrow(listing) == 0L) return(character())
  listing$name[!listing$is_dir]
}

# Listing mode: files matching a glob, full depth. Never reads any of them.
.raw_glob_listing <- function(conn, pattern) {
  listing <- gdpins_raw_ls(conn, depth = Inf)
  listing <- listing[!listing$is_dir, , drop = FALSE]
  matched <- fs::path_filter(listing$name, glob = pattern)
  .new_raw_listing(listing[listing$name %in% matched, , drop = FALSE])
}

# Bullet list of candidate paths for error messages, capped so a wide
# connection cannot flood the console.
.raw_suggest_bullets <- function(paths, max_n = 5L) {
  # cli interpolates {...}; a filename may legally contain braces, so escape
  # them rather than let a stray "{" turn a helpful error into a glue failure.
  esc <- function(x) {
    gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
  }
  shown      <- utils::head(paths, max_n)
  out        <- esc(shown)
  names(out) <- rep("*", length(out))
  if (length(paths) > max_n) {
    extra        <- paste0("... and ", length(paths) - max_n, " more")
    names(extra) <- "i"
    out <- c(out, extra)
  }
  out
}

#' Resolve a user-supplied name to a file in a raw connection
#'
#' Walks the name-resolution ladder documented on [raw-connection]. Auto-resolve
#' happens only where the match is both exact and unique (rungs 1, 2, 4); every
#' looser rung only ever *suggests*, via an error.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param name Character scalar. The name as the user typed it.
#' @param verb Character scalar. Calling verb, used in error text.
#'
#' @return Character scalar. A relative path known to the connection.
#' @keywords internal
.resolve_raw_name <- function(conn, name, verb = "gdpins_raw_path") {
  # Rung 1 -- exact relative path. Checked against the local mirror first so a
  # file that is already here never triggers a Drive listing.
  if (.local_exists_exact(conn, name)) return(name)

  cands <- .raw_file_candidates(conn)
  if (name %in% cands) return(name)

  glob_hint <- paste0(verb, '(conn, "*")')

  if (length(cands) == 0L) {
    cli::cli_abort(c(
      "File not found in raw connection: {.path {name}}",
      x = "The connection has no files.",
      i = "Add one with {.fn gdpins_raw_put_file} or {.fn gdpins_raw_put_object}."
    ))
  }

  base_q <- basename(name)
  bases  <- basename(cands)

  # Rungs 2/3 -- exact basename.
  by_base <- cands[bases == base_q]
  if (length(by_base) > 1L) {
    cli::cli_abort(c(
      "Ambiguous name {.val {name}}: {length(by_base)} files share that name.",
      i = "Use the full relative path. Matches:",
      .raw_suggest_bullets(by_base, max_n = length(by_base))
    ))
  }
  if (length(by_base) == 1L) return(by_base)

  # Rung 4 -- case-insensitive exact, on the full path or the basename.
  ci <- cands[tolower(cands) == tolower(name) | tolower(bases) == tolower(base_q)]
  ci <- unique(ci)
  if (length(ci) == 1L) return(ci)

  # Everything below only suggests.
  near <- unique(c(by_base, ci))

  # Rung 5 -- same stem, different extension. Distance-exempt: "cars.csv" should
  # find "cars.parquet" however far apart the extensions look.
  stem_q  <- tools::file_path_sans_ext(base_q)
  by_stem <- cands[tolower(tools::file_path_sans_ext(bases)) == tolower(stem_q)]
  near    <- unique(c(near, by_stem))

  # Rung 6 -- edit distance on the lowercased basename.
  if (length(near) == 0L) {
    d   <- utils::adist(tolower(base_q), tolower(bases))[1L, ]
    thr <- max(2L, floor(0.34 * nchar(base_q)))
    within <- which(d <= thr)
    near   <- cands[within[order(d[within])]]
    near   <- utils::head(near, 5L)
  }

  # Rung 7 -- nothing close.
  if (length(near) == 0L) {
    root <- if (!is.null(conn$drive_path)) conn$drive_path else conn$local_path
    cli::cli_abort(c(
      "File not found in raw connection: {.path {name}}",
      i = "Connection root: {.path {root}}",
      i = "List everything with {.code {glob_hint}}."
    ))
  }

  cli::cli_abort(c(
    "File not found in raw connection: {.path {name}}",
    i = "Did you mean:",
    .raw_suggest_bullets(near),
    i = "List everything with {.code {glob_hint}}."
  ))
}

# Serialise x to a temp file using the writer for ext; return temp path
.raw_write_tmp <- function(x, name, wkt_engine = NULL) {
  ext  <- .check_ext(name)
  tmp  <- tempfile(fileext = ext)

  switch(
    ext,
    ".rds"     = saveRDS(x, tmp),
    ".parquet" = {
      if (inherits(x, "sf")) {
        encoded <- gdpins_sf_to_parquet(x, engine = wkt_engine)
        arrow::write_parquet(encoded, tmp)
      } else {
        arrow::write_parquet(x, tmp)
      }
    },
    ".geojson" = sf::st_write(x, tmp, quiet = TRUE),
    ".csv"     = readr::write_csv(x, tmp)
  )

  tmp
}

# Read from a local file path using the reader for the extension
.raw_read_local <- function(local_file, wkt_engine = NULL) {
  ext <- .raw_ext(local_file)
  .check_ext(local_file)  # errors on unknown

  switch(
    ext,
    ".rds"     = readRDS(local_file),
    ".parquet" = {
      # mmap = FALSE: memory-mapping local files crashes the R session with an
      # access violation when the file lives on a cloud-sync mount (OneDrive/
      # SharePoint Files On-Demand) that can invalidate or rewrite the backing
      # pages while Arrow still holds the mapping. A buffered read is slightly
      # slower but never segfaults.
      tbl <- arrow::read_parquet(local_file, mmap = FALSE)
      # Route through gdpins_parquet_to_sf if encoded geometry columns present
      gdpins_parquet_to_sf(tbl, engine = wkt_engine)
    },
    ".geojson" = sf::st_read(local_file, quiet = TRUE),
    ".csv"     = readr::read_csv(local_file, show_col_types = FALSE)
  )
}

# Build the full Drive path for a name relative to conn$drive_path
.drive_full_path <- function(conn, name) {
  paste0(conn$drive_path, "/", name)
}

# Build the full local path for a name relative to conn$local_path
.local_full_path <- function(conn, name) {
  file.path(conn$local_path, gsub("/", .Platform$file.sep, name, fixed = TRUE))
}

# Normalise paths returned by gd_ls (may be absolute on Windows fake adapter)
# Strips the adapter root prefix + drive_path prefix to get names relative to
# drive_path. Returns a character vector of "/" separated relative names.
.gd_ls_to_rel <- function(paths, adapter, drive_path) {
  if (length(paths) == 0L) return(character(0L))

  # Strip adapter root if present (fake adapter on Windows returns abs paths)
  adapter_root <- if (!is.null(adapter$root)) adapter$root else ""
  if (nzchar(adapter_root)) {
    # Normalise separators
    adapter_root_norm <- gsub("\\\\", "/", normalizePath(adapter_root, mustWork = FALSE))
    paths <- gsub("\\\\", "/", paths)
    paths <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                  adapter_root_norm), "/?"), "", paths)
  }

  # Now strip drive_path prefix if present
  prefix <- paste0(drive_path, "/")
  paths  <- sub(paste0("^", prefix), "", paths)

  paths
}

# Normalize relative path vectors for stable comparison across platforms/shells.
.normalize_rel_paths <- function(paths, dedupe = TRUE) {
  if (length(paths) == 0L) return(character(0L))
  norm <- as.character(paths)
  norm <- gsub("\\\\", "/", norm)
  norm <- gsub("^\\./+", "", norm)
  norm <- gsub("/+", "/", norm)
  norm <- sub("^/+", "", norm)
  norm <- sub("/+$", "", norm)
  if (.Platform$OS.type == "windows") {
    norm <- tolower(norm)
  }
  if (isTRUE(dedupe)) {
    norm <- unique(norm[nzchar(norm)])
  }
  norm
}

# Ignore common sync/system sidecars that should not trigger raw sync decisions.
.is_sync_sidecar <- function(paths) {
  if (length(paths) == 0L) return(logical(0L))
  base <- tolower(basename(.normalize_rel_paths(paths, dedupe = FALSE)))
  base %in% c("desktop.ini", "thumbs.db", ".ds_store") | grepl("^~\\$", base)
}

.discrepancy_paths <- function(paths) {
  norm <- .normalize_rel_paths(paths, dedupe = FALSE)
  unique(norm[nzchar(norm) & !.is_sync_sidecar(norm)])
}

# Build a Drive URL from a Drive ID and a logical is_dir flag (vectorised).
# Returns NA_character_ wherever drive_id is NA.
.make_drive_url <- function(drive_id, is_dir) {
  url <- ifelse(
    is.na(drive_id),
    NA_character_,
    ifelse(
      is_dir,
      paste0("https://drive.google.com/drive/folders/", drive_id),
      paste0("https://drive.google.com/file/d/", drive_id, "/view")
    )
  )
  as.character(url)
}

# ── gdpins_raw_connect ────────────────────────────────────────────────────────

#' Connect to a raw-exogenous Drive folder
#'
#' Creates a `gdpins_raw_conn` object pointing at a Drive raw-root and its
#' local mirror. On connect, checks for sync discrepancies and whether the
#' Drive folder exists (controlled by `create` and `on_discrepancy`).
#'
#' @param drive_path Character scalar. Drive raw-root path (relative to the
#'   adapter root), or `NULL` for `"local_only"`.
#' @param local_path Character scalar. Local mirror directory path.
#' @param create Logical or `NA`. Controls Drive folder creation: `TRUE` =
#'   create if absent; `FALSE` = error if absent; `NA` = interactive prompt.
#' @param on_discrepancy Character scalar or `NULL`. One of
#'   `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`. `NULL`
#'   resolves at runtime.
#' @param adapter A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.
#'
#' @return A `gdpins_raw_conn` object.
#' @seealso [gdpins_real_drive()] and [gdpins_ensure_drive_auth()] for auth and
#'   adapter setup, [gdpins_raw_remove()], [gdpins_go_offline()] to
#'   temporarily detach an existing connection from Drive and work locally.
#' @examples
#' # --- Fake adapter (no network) ---
#' adapter <- gdpins_fake_drive()
#' conn <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = tempfile("raw_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' conn
#'
#' # --- Real adapter ---
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' conn <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = "data/raw/worldbank-api",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#'
#' # Supply a Drive folder ID directly as drive_path
#' conn2 <- gdpins_raw_connect(
#'   drive_path = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
#'   local_path = "data/raw/worldbank-api",
#'   adapter    = adapter
#' )
#' }
#' @family raw-connection
#' @export
gdpins_raw_connect <- function(
    drive_path,
    local_path,
    create         = NA,
    on_discrepancy = NULL,
    adapter        = NULL
) {
  # Validate local_path
  if (!is.character(local_path) || length(local_path) != 1L || !nzchar(local_path)) {
    cli::cli_abort("{.arg local_path} must be a non-empty character scalar.")
  }

  # Resolve on_discrepancy
  disc <- .resolve_on_discrepancy(on_discrepancy)

  # Determine config
  if (is.null(adapter)) {
    # local_only: no Drive interaction
    fs::dir_create(local_path)
    return(new_gdpins_raw_conn(
      config     = "local_only",
      local_path = local_path
    ))
  }

  # drive_local: validate drive_path
  if (is.null(drive_path) || !is.character(drive_path) ||
      length(drive_path) != 1L || !nzchar(drive_path)) {
    cli::cli_abort(
      "{.arg drive_path} must be a non-empty character scalar when {.arg adapter} is provided."
    )
  }

  # Create-confirm logic for Drive folder
  drive_exists <- gd_exists(adapter, drive_path)

  # Real adapter + drive_path looks like a Drive ID: verify directly, no create
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
    fs::dir_create(local_path)
    return(new_gdpins_raw_conn(
      config     = "drive_local",
      drive_path = drive_path,
      local_path = local_path,
      adapter    = adapter
    ))
    # nocov end
  }

  if (!drive_exists) {
    if (isTRUE(create)) {
      gd_mkdir(adapter, drive_path)
    } else if (isFALSE(create)) {
      cli::cli_abort(c(
        "Drive path {.val {drive_path}} does not exist.",
        i = "Set {.code create = TRUE} to create it."
      ))
    } else {
      # create = NA: prompt if interactive, else error
      if (.raw_is_interactive()) {
        answer <- .raw_readline(
          paste0("Drive path '", drive_path, "' not found. Create? [y/N] ")
        )
        if (tolower(trimws(answer)) == "y") {
          gd_mkdir(adapter, drive_path)
        } else {
          cli::cli_abort(
            "Drive path {.val {drive_path}} does not exist and creation was declined."
          )
        }
      } else {
        cli::cli_abort(c(
          "Drive path {.val {drive_path}} does not exist.",
          i = "Set {.code create = TRUE} to create it, or run interactively to be prompted."
        ))
      }
    }
  }

  # Ensure local mirror exists
  fs::dir_create(local_path)

  # Init-time sync check: compare Drive vs local
  drive_listing <- gd_ls(adapter, drive_path, recursive = TRUE)
  drive_all_rel <- .gd_ls_to_rel(drive_listing$path, adapter, drive_path)
  drive_files   <- drive_all_rel[!drive_listing$is_dir]

  # Local files (relative to local_path, "/" separated)
  local_abs <- fs::dir_ls(local_path, recurse = TRUE, type = "file", all = FALSE)
  local_rel <- if (length(local_abs) == 0L) {
    character(0L)
  } else {
    root_norm <- gsub("\\\\", "/",
                      normalizePath(local_path, mustWork = FALSE))
    vapply(as.character(local_abs), function(p) {
      p_norm <- gsub("\\\\", "/", normalizePath(p, mustWork = FALSE))
      rel    <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                     root_norm), "/?"), "", p_norm)
      rel
    }, character(1L), USE.NAMES = FALSE)
  }

  drive_cmp <- .discrepancy_paths(drive_files)
  local_cmp <- .discrepancy_paths(local_rel)

  has_discrepancy <- !setequal(drive_cmp, local_cmp)

  if (has_discrepancy) {
    switch(
      disc,
      "prompt" = {
        if (.raw_is_interactive()) {
          cli::cli_alert_warning(
            "Drive and local mirror differ for {.val {drive_path}}."
          )
          answer <- .raw_readline("Sync from Drive? [y/N] ")
          if (tolower(trimws(answer)) == "y") {
            for (f in drive_files[!.is_sync_sidecar(drive_files)]) {
              local_dest <- file.path(local_path,
                                      gsub("/", .Platform$file.sep, f, fixed = TRUE))
              fs::dir_create(dirname(local_dest))
              gd_download(adapter, paste0(drive_path, "/", f), local_dest)
            }
          }
        } else {
          cli::cli_warn(
            "Drive and local mirror differ for {.val {drive_path}}. Run interactively to sync."
          )
        }
      },
      "warn" = {
        cli::cli_warn(
          "Drive and local mirror differ for {.val {drive_path}}."
        )
      },
      "sync_from_drive" = {
        for (f in drive_files[!.is_sync_sidecar(drive_files)]) {
          local_dest <- file.path(local_path,
                                  gsub("/", .Platform$file.sep, f, fixed = TRUE))
          fs::dir_create(dirname(local_dest))
          gd_download(adapter, paste0(drive_path, "/", f), local_dest)
        }
      },
      "sync_to_drive" = {
        for (f in local_rel[!.is_sync_sidecar(local_rel)]) {
          local_src  <- file.path(local_path,
                                  gsub("/", .Platform$file.sep, f, fixed = TRUE))
          drive_dest <- paste0(drive_path, "/", f)
          gd_upload(adapter, local_src, drive_dest)
        }
      },
      "ignore" = {
        # do nothing
      }
    )
  }

  new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = drive_path,
    local_path = local_path,
    adapter    = adapter
  )
}

# ── gdpins_raw_put_object ─────────────────────────────────────────────────────

#' Write an R object to a raw connection
#'
#' Serialises `x` to a temp file using the appropriate writer for the extension
#' in `name`, then deposits it to Drive and mirrors locally.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param x An R object.
#' @param name Character scalar. Relative path within the raw-root, including
#'   extension (e.g. `"worldbank-api/gdp_2024.parquet"`).
#' @param wkt_engine Character scalar or `NULL`. WKT engine used to encode `sf`
#'   geometry when writing `.parquet`: `"wk"` (default) or `"sf"`. `NULL` uses
#'   the `gdpins.wkt_engine` option. See [gdpins_sf_to_parquet()].
#'
#' @return Invisibly `NULL`.
#' @inheritSection raw-connection Objects vs paths
#' @family raw-connection
#' @export
gdpins_raw_put_object <- function(conn, x, name, wkt_engine = NULL) {
  .check_ext(name)

  tmp        <- .raw_write_tmp(x, name, wkt_engine = wkt_engine)
  on.exit(unlink(tmp), add = TRUE)

  local_dest <- .local_full_path(conn, name)
  fs::dir_create(dirname(local_dest))
  fs::file_copy(tmp, local_dest, overwrite = TRUE)

  if (!is.null(conn$adapter)) {
    drive_dest <- .drive_full_path(conn, name)
    gd_upload(conn$adapter, local_dest, drive_dest)
  }

  invisible(NULL)
}

# ── gdpins_raw_put_file ───────────────────────────────────────────────────────

#' Upload a file verbatim to a raw connection
#'
#' Copies a local file byte-for-byte to Drive and mirrors locally. No R
#' round-trip, no coercion — byte-faithful upload.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param path Character scalar. Path to the local source file.
#' @param name Character scalar. Relative destination path within the raw-root.
#'
#' @return Invisibly `NULL`.
#' @inheritSection raw-connection Objects vs paths
#' @family raw-connection
#' @export
gdpins_raw_put_file <- function(conn, path, name) {
  if (!file.exists(path)) {
    cli::cli_abort("Source file not found: {.path {path}}")
  }

  # Any extension, but there must be one. Deliberately NOT .check_ext(): this
  # verb uploads bytes verbatim, so restricting it to the four readable formats
  # would reject .gpkg/.tif/.xlsx -- precisely what it exists to carry. An
  # extension is still required so the file stays identifiable on Drive.
  if (!nzchar(tools::file_ext(name))) {
    cli::cli_abort(c(
      "{.arg name} must include a file extension.",
      x = "Got {.val {name}}.",
      i = "Any extension is accepted (e.g. {.val .gpkg}, {.val .tif}, {.val .xlsx});
           it is kept verbatim on Drive."
    ))
  }

  local_dest <- .local_full_path(conn, name)
  fs::dir_create(dirname(local_dest))
  fs::file_copy(path, local_dest, overwrite = TRUE)

  if (!is.null(conn$adapter)) {
    drive_dest <- .drive_full_path(conn, name)
    gd_upload(conn$adapter, local_dest, drive_dest)
  }

  invisible(NULL)
}

#' Remove a file from a raw connection
#'
#' Deletes a single file from the local mirror and, when Drive is configured,
#' moves the Drive file to trash (recoverable). Missing files are ignored
#' (idempotent no-op). Folder-recursive deletion is not supported.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param name Character scalar. Relative file path within the raw-root.
#'
#' @return Invisibly `NULL`.
#' @seealso [gdpins_raw_put_object()], [gdpins_raw_put_file()], [gdpins_raw_get()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' conn <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = tempfile("raw_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_raw_put_object(conn, mtcars, "cars.csv")
#' gdpins_raw_remove(conn, "cars.csv")
#' @inheritSection raw-connection Name resolution
#' @inheritSection raw-connection Glob and listing mode
#' @family raw-connection
#' @export
gdpins_raw_remove <- function(conn, name) {
  if (!inherits(conn, "gdpins_raw_conn")) {
    cli::cli_abort(c(
      "{.arg conn} must be a {.cls gdpins_raw_conn}.",
      x = "Got {.cls {class(conn)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  # Listing mode. Never bulk-deletes -- a glob shows what *would* match, and the
  # caller removes files one exact path at a time.
  if (.is_glob(name)) {
    return(.raw_glob_listing(conn, name))
  }

  # Rung 1 only -- the name-resolution ladder is deliberately NOT applied here.
  # Removal hard-deletes the local copy, and auto-resolving a near-miss onto a
  # real file is exactly the guess a delete-guarded package must never make.
  # Missing targets stay an idempotent no-op, so there is no error path to hang
  # "did you mean" suggestions on.
  #
  # Both sides are gated on a case-exact hit, and nothing is touched unless one
  # of them hits. A bare file.exists() / adapter-side lookup is case-insensitive
  # on Windows, which would make "CARS.CSV" delete cars.csv on one platform and
  # no-op on another -- the exact guess this rung exists to forbid.
  found_local <- .local_exists_exact(conn, name)

  # Drive is the truth, so a file can be there without being mirrored. Only
  # listed when the local check missed: the listing costs a Drive call.
  found_drive <- !found_local && !is.null(conn$adapter) &&
    name %in% .raw_file_candidates(conn)

  if (!found_local && !found_drive) return(invisible(NULL))

  if (found_local) {
    fs::file_delete(.local_full_path(conn, name))
  }

  if (!is.null(conn$adapter)) {
    gd_trash(conn$adapter, .drive_full_path(conn, name))
  }

  invisible(NULL)
}

# ── gdpins_raw_path ───────────────────────────────────────────────────────────

#' Resolve a raw file to its absolute local path
#'
#' Given either a relative path within the raw-root (e.g. `"sub/data.csv"`) or
#' a Google Drive file ID, returns the absolute local filesystem path to the
#' file, downloading it from Drive if it is not already present locally.
#'
#' Files that already exist in the local mirror are **never** re-downloaded.
#' Call [gdpins_raw_get()] with `force_refresh = TRUE` if you need to guarantee
#' freshness.
#'
#' @param conn A `gdpins_raw_conn` object created by [gdpins_raw_connect()].
#' @param name_or_id Character scalar. Either:
#'   \describe{
#'     \item{Relative path}{A path within the raw-root, using `"/"` as
#'       separator (e.g. `"api/gdp_2024.parquet"` or `"my data (2024).csv"`).}
#'     \item{Drive file ID}{A Google Drive file ID (≥ 25 alphanumeric
#'       characters, no slashes or hyphens). Only supported with a real adapter.}
#'   }
#'
#' @return Character scalar. Absolute local filesystem path to the file.
#'   The file is guaranteed to exist when a non-error value is returned.
#'
#' @details
#' **Resolution order:**
#' 1. If `name_or_id` looks like a Drive ID (≥ 25 purely alphanumeric chars):
#'    - Errors on local-only connections (no Drive adapter).
#'    - Errors on fake-adapter connections (fake adapter has no real IDs).
#'    - On real adapters: fetches file metadata via `googledrive::drive_get()`,
#'      downloads to `conn$local_path/<filename>`, and returns the path.
#' 2. Otherwise treated as a relative path:
#'    - Returns the local path immediately if the file already exists.
#'    - Downloads from Drive if not present (drive-backed connections only).
#'    - Errors if local-only and the file is missing.
#'
#' @seealso [gdpins_raw_ls()] to list files and obtain their paths,
#'   [gdpins_raw_get()] to read a file as an R object,
#'   [gdpins_raw_connect()] to create a connection.
#'
#' @examples
#' adapter <- gdpins_fake_drive()
#' conn <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = tempfile("raw_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_raw_put_object(conn, mtcars, "cars.csv")
#'
#' # Already local — returns path immediately, no download
#' path <- gdpins_raw_path(conn, "cars.csv")
#' file.exists(path)   # TRUE
#' read.csv(path)      # read directly with base R
#'
#' # Non-standard filenames work too
#' gdpins_raw_put_object(conn, mtcars, "quarterly report (Q1 2024).csv")
#' gdpins_raw_path(conn, "quarterly report (Q1 2024).csv")
#'
#' \dontrun{
#' # Drive ID input — real adapter only
#' adapter_real <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' conn_real <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = "data/raw/worldbank-api",
#'   adapter    = adapter_real
#' )
#' # Obtain drive_id from gdpins_raw_ls(), then fetch by ID
#' listing <- gdpins_raw_ls(conn_real)
#' file_id <- listing$drive_id[listing$name == "gdp_2024.parquet"]
#' local_path <- gdpins_raw_path(conn_real, file_id)
#' arrow::read_parquet(local_path)
#' }
#' @inheritSection raw-connection Name resolution
#' @inheritSection raw-connection Glob and listing mode
#' @inheritSection raw-connection Objects vs paths
#' @family raw-connection
#' @export
gdpins_raw_path <- function(conn, name_or_id) {
  if (!inherits(conn, "gdpins_raw_conn")) {
    cli::cli_abort(c(
      "{.arg conn} must be a {.cls gdpins_raw_conn}.",
      x = "Got {.cls {class(conn)}}."
    ))
  }
  if (!is.character(name_or_id) || length(name_or_id) != 1L || !nzchar(name_or_id)) {
    cli::cli_abort("{.arg name_or_id} must be a non-empty character scalar.")
  }

  # ── Listing branch ───────────────────────────────────────────────────────────
  # Checked before the Drive-ID heuristic: a Drive ID is purely alphanumeric and
  # so can never contain "*" or "?".
  if (.is_glob(name_or_id)) {
    return(.raw_glob_listing(conn, name_or_id))
  }

  # ── Drive ID branch ──────────────────────────────────────────────────────────
  if (.is_drive_id(name_or_id)) {
    if (is.null(conn$adapter)) {
      cli::cli_abort(c(
        "Cannot resolve a Drive file ID from a local-only connection.",
        i = "Use {.fn gdpins_raw_connect} with an adapter for Drive ID lookups.",
        i = "Alternatively, supply a relative file path instead of a Drive ID."
      ))
    }
    if (identical(conn$adapter$kind, "fake")) {
      cli::cli_abort(c(
        "The fake adapter carries no real Drive IDs.",
        i = "Drive ID lookup requires a real adapter created by {.fn gdpins_real_drive}.",
        i = "For tests or offline use, supply a relative file path."
      ))
    }

    # nocov start — requires live Google Drive auth
    d <- tryCatch(
      googledrive::drive_get(googledrive::as_id(name_or_id)),
      error = function(e) {
        cli::cli_abort("Drive ID lookup failed: {conditionMessage(e)}")
      }
    )
    if (is.null(d) || nrow(d) == 0L) {
      cli::cli_abort(c(
        "Drive file ID not found: {.val {name_or_id}}",
        i = "Verify the ID exists and is accessible with your current credentials."
      ))
    }
    filename   <- d$name[[1L]]
    local_dest <- file.path(conn$local_path, filename)
    if (file.exists(local_dest)) return(local_dest)
    fs::dir_create(dirname(local_dest))
    googledrive::drive_download(d, path = local_dest, overwrite = TRUE)
    return(local_dest)
    # nocov end
  }

  # ── Relative path branch ─────────────────────────────────────────────────────
  # Fast path: already mirrored locally under exactly this spelling, so there is
  # nothing to resolve and no reason to list Drive.
  if (.local_exists_exact(conn, name_or_id)) {
    return(.local_full_path(conn, name_or_id))
  }

  # Walk the ladder. Auto-resolves only on an exact, unique match; otherwise it
  # aborts with suggestions, so anything returned here is a real relative path.
  name       <- .resolve_raw_name(conn, name_or_id, verb = "gdpins_raw_path")
  local_dest <- .local_full_path(conn, name)
  if (file.exists(local_dest)) return(local_dest)

  if (!is.null(conn$adapter)) {
    drive_src <- .drive_full_path(conn, name)
    if (!gd_exists(conn$adapter, drive_src)) {
      cli::cli_abort(c(
        "File not found on Drive: {.path {name}}",
        i = "Check the path with {.fn gdpins_raw_ls} or upload the file first."
      ))
    }
    fs::dir_create(dirname(local_dest))
    gd_download(conn$adapter, drive_src, local_dest)
    return(local_dest)
  }

  cli::cli_abort(c(
    "Local file not found: {.path {local_dest}}",
    i = "This is a local-only connection; there is no Drive source to download from.",
    i = "Use {.fn gdpins_raw_put_file} or {.fn gdpins_raw_put_object} to add the file."
  ))
}

# ── gdpins_raw_get ────────────────────────────────────────────────────────────

#' Read a file from a raw connection
#'
#' Reads a file from the local mirror by default. Set `force_refresh = TRUE` to
#' re-pull from Drive first.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param name Character scalar. Relative path within the raw-root.
#' @param force_refresh Logical. `TRUE` re-pulls from Drive before reading.
#'   Default `FALSE`.
#' @param wkt_engine Character scalar or `NULL`. WKT engine used to decode `sf`
#'   geometry when reading `.parquet`: `"wk"` (default) or `"sf"`. `NULL` uses
#'   the `gdpins.wkt_engine` option. Reads are engine-agnostic. See
#'   [gdpins_parquet_to_sf()].
#'
#' @return The deserialised R object.
#' @inheritSection raw-connection Name resolution
#' @inheritSection raw-connection Glob and listing mode
#' @inheritSection raw-connection Objects vs paths
#' @family raw-connection
#' @export
gdpins_raw_get <- function(conn, name, force_refresh = FALSE, wkt_engine = NULL) {
  if (!inherits(conn, "gdpins_raw_conn")) {
    cli::cli_abort(c(
      "{.arg conn} must be a {.cls gdpins_raw_conn}.",
      x = "Got {.cls {class(conn)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  # Listing mode never reads: a glob asks what is there, not for its contents.
  if (.is_glob(name)) {
    return(.raw_glob_listing(conn, name))
  }

  # Resolve before touching the extension, so a near-miss reports "did you mean"
  # rather than complaining about the extension of a file that does not exist.
  if (!.local_exists_exact(conn, name)) {
    name <- .resolve_raw_name(conn, name, verb = "gdpins_raw_get")
  }

  # Refuse unreadable formats up front, and point at the verb that does work.
  .check_ext_get(name)

  local_file <- .local_full_path(conn, name)

  if (isTRUE(force_refresh) && !is.null(conn$adapter)) {
    drive_src <- .drive_full_path(conn, name)
    fs::dir_create(dirname(local_file))
    gd_download(conn$adapter, drive_src, local_file)
  }

  # Deliberately does NOT auto-download: gdpins_raw_get() reads the local mirror
  # by default, and force_refresh is the documented way to reach Drive.
  if (!file.exists(local_file)) {
    cli::cli_abort(c(
      "Local file not found: {.path {local_file}}",
      i = "Use {.code force_refresh = TRUE} to pull from Drive first.",
      i = "Or call {.code gdpins_raw_path(conn, {.str {name}})}, which downloads on demand."
    ))
  }

  .raw_read_local(local_file, wkt_engine = wkt_engine)
}

# ── gdpins_raw_ls ─────────────────────────────────────────────────────────────

#' List contents of a raw connection
#'
#' Returns a compact folder tree for the raw connection, defaulting to 2 levels
#' of depth.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param depth Integer scalar. Maximum directory depth to display. Default `2`.
#'
#' @return A [tibble::tibble()] with 8 columns:
#'   \describe{
#'     \item{`name`}{chr. Relative path within the raw-root.}
#'     \item{`is_dir`}{lgl. `TRUE` for directories, `FALSE` for files.}
#'     \item{`size`}{dbl. File size in bytes (0 for directories).}
#'     \item{`mtime`}{POSIXct. Last-modified time.}
#'     \item{`depth`}{int. Directory depth (1 = top-level).}
#'     \item{`local_path`}{chr. Absolute local filesystem path.}
#'     \item{`drive_id`}{chr. Google Drive file/folder ID, or `NA_character_`
#'       for local-only connections and the fake adapter.}
#'     \item{`drive_url`}{chr. Browser URL for the entry
#'       (`https://drive.google.com/file/d/<id>/view` for files,
#'       `https://drive.google.com/drive/folders/<id>` for folders), or
#'       `NA_character_` when `drive_id` is `NA`.}
#'   }
#' @examples
#' adapter <- gdpins_fake_drive()
#' conn <- gdpins_raw_connect(
#'   drive_path = "worldbank-api",
#'   local_path = tempfile("raw_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_raw_put_object(conn, mtcars, "cars.csv")
#' tbl <- gdpins_raw_ls(conn)
#' tbl$local_path   # absolute local path
#' tbl$drive_id     # NA for fake adapter; real Drive ID with real adapter
#' @inheritSection raw-connection Glob and listing mode
#' @family raw-connection
#' @export
gdpins_raw_ls <- function(conn, depth = 2) {
  empty <- .new_raw_listing(tibble::tibble(
    name       = character(),
    is_dir     = logical(),
    size       = double(),
    mtime      = as.POSIXct(character()),
    depth      = integer(),
    local_path = character(),
    drive_id   = character(),
    drive_url  = character()
  ))

  if (!is.null(conn$adapter)) {
    # Drive-backed: use gd_ls with recursive = TRUE then filter by depth
    listing <- gd_ls(conn$adapter, conn$drive_path, recursive = TRUE)
    if (nrow(listing) == 0L) return(empty)

    # Normalise absolute paths returned by the fake adapter
    rel_path <- .gd_ls_to_rel(listing$path, conn$adapter, conn$drive_path)

    # Compute depth (number of path components)
    entry_depth <- vapply(rel_path, function(p) {
      length(strsplit(p, "/", fixed = TRUE)[[1L]])
    }, integer(1L), USE.NAMES = FALSE)

    # Filter by depth
    keep        <- entry_depth <= depth
    rel_path    <- rel_path[keep]
    entry_depth <- entry_depth[keep]
    listing     <- listing[keep, , drop = FALSE]

    local_path_col <- file.path(
      conn$local_path,
      gsub("/", .Platform$file.sep, rel_path, fixed = TRUE)
    )
    drive_id_col  <- listing$drive_id
    drive_url_col <- .make_drive_url(drive_id_col, listing$is_dir)

    .new_raw_listing(tibble::tibble(
      name       = rel_path,
      is_dir     = listing$is_dir,
      size       = listing$size,
      mtime      = listing$mtime,
      depth      = entry_depth,
      local_path = local_path_col,
      drive_id   = drive_id_col,
      drive_url  = drive_url_col
    ))
  } else {
    # local_only
    abs_paths <- fs::dir_ls(conn$local_path, recurse = TRUE, all = FALSE)

    if (length(abs_paths) == 0L) return(empty)

    root_norm <- gsub("\\\\", "/",
                      normalizePath(conn$local_path, mustWork = FALSE))
    rel_paths <- vapply(as.character(abs_paths), function(p) {
      p_norm <- gsub("\\\\", "/", normalizePath(p, mustWork = FALSE))
      rel    <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                     root_norm), "/?"), "", p_norm)
      rel
    }, character(1L), USE.NAMES = FALSE)

    entry_depth <- vapply(rel_paths, function(p) {
      length(strsplit(p, "/", fixed = TRUE)[[1L]])
    }, integer(1L), USE.NAMES = FALSE)

    keep     <- entry_depth <= depth
    abs_keep <- as.character(abs_paths)[keep]
    rel_keep <- rel_paths[keep]
    dep_keep <- entry_depth[keep]

    .new_raw_listing(tibble::tibble(
      name       = rel_keep,
      is_dir     = fs::is_dir(abs_keep),
      size       = vapply(abs_keep, function(p) {
        if (fs::is_dir(p)) 0 else as.double(file.size(p))
      }, double(1L), USE.NAMES = FALSE),
      mtime      = file.mtime(abs_keep),
      depth      = dep_keep,
      local_path = abs_keep,
      drive_id   = rep(NA_character_, length(rel_keep)),
      drive_url  = rep(NA_character_, length(rel_keep))
    ))
  }
}

# ── gdpins_refresh_disconnect ─────────────────────────────────────────────────

#' Force-refresh a raw connection and disconnect
#'
#' Pulls all files from Drive to the local mirror, then invalidates the
#' connection object.
#'
#' @param conn A `gdpins_raw_conn` object.
#'
#' @return Invisibly `NULL`.
#' @family raw-connection
#' @export
gdpins_refresh_disconnect <- function(conn) {
  if (!is.null(conn$adapter)) {
    listing     <- gd_ls(conn$adapter, conn$drive_path, recursive = TRUE)
    all_rel     <- .gd_ls_to_rel(listing$path, conn$adapter, conn$drive_path)
    drive_files <- all_rel[!listing$is_dir]

    for (rel in drive_files) {
      local_dest <- .local_full_path(conn, rel)
      fs::dir_create(dirname(local_dest))
      gd_download(conn$adapter, paste0(conn$drive_path, "/", rel), local_dest)
    }
  }

  invisible(NULL)
}

# ── S3 methods ────────────────────────────────────────────────────────────────

# Truncate a path string to fit within max_width characters
.truncate_path <- function(path, max_width = 60L) {
  if (nchar(path) <= max_width) return(path)
  paste0("...", substr(path, nchar(path) - max_width + 4L, nchar(path)))
}

#' @export
#' @exportS3Method format gdpins_raw_conn
format.gdpins_raw_conn <- function(x, ...) {
  config_lbl <- if (x$config == "drive_local") "drive+local" else "local only"
  local_disp <- .truncate_path(x$local_path, 55L)
  lines <- c(
    paste0("<gdpins_raw_conn> [", config_lbl, "]"),
    paste0("  local: ", local_disp)
  )
  if (!is.null(x$drive_path)) {
    drive_disp <- .truncate_path(x$drive_path, 55L)
    lines <- c(lines, paste0("  drive: ", drive_disp))
  }
  paste(lines, collapse = "\n")
}

#' @export
#' @exportS3Method print gdpins_raw_conn
print.gdpins_raw_conn <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

#' @export
#' @exportS3Method summary gdpins_raw_conn
summary.gdpins_raw_conn <- function(object, ...) {
  config_lbl <- if (object$config == "drive_local") "drive+local" else "local only"
  cli::cli_text("<gdpins_raw_conn> [{config_lbl}]")
  gd_cli_kv(local = object$local_path)
  if (!is.null(object$drive_path)) {
    gd_cli_kv(drive = object$drive_path)
  }
  gd_cli_kv(config = object$config)

  # Count local files
  local_files <- tryCatch(
    length(fs::dir_ls(object$local_path, recurse = TRUE, type = "file")),
    error = function(e) NA_integer_
  )
  gd_cli_kv(files = if (is.na(local_files)) "?" else as.character(local_files))

  invisible(object)
}
