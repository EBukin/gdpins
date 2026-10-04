# Name and path validation
#
# Pin names and raw file names are joined onto local directories and Drive
# paths. A name such as ".." or "../x.csv" would otherwise reach outside the
# board or the raw connection's local_path (audit H1, H2). User-supplied names
# are rejected with `gdpins_error_invalid_name`; names that come from a Drive
# listing are skipped in bulk loops with `gdpins_warning_invalid_name`; every
# joined local path is checked against its root and rejected with
# `gdpins_error_path_escape`.

#' Validate a pin name
#'
#' A pin name must be a non-empty character scalar that is not `"."` or `".."`,
#' does not start with a dot, and contains no path separator or control
#' character.
#'
#' @param name Value to check.
#' @param arg Argument name used in the error message.
#' @param call Environment of the calling verb, shown in the error.
#'
#' @return `name`, invisibly.
#' @keywords internal
#' @noRd
.check_pin_name <- function(name, arg = rlang::caller_arg(name),
                            call = rlang::caller_env()) {
  .check_name_scalar(name, arg = arg, call = call)
  if (name %in% c(".", "..") || startsWith(name, ".") ||
      grepl("[/\\\\]", name, useBytes = TRUE) ||
      grepl("[[:cntrl:]]", name, useBytes = TRUE)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} is not a valid pin name: {.val {name}}.",
        i = paste(
          "A pin name cannot be {.val .} or {.val ..}, start with a dot, or",
          "contain a path separator or control character."
        )
      ),
      class = c("gdpins_error_invalid_name", "gdpins_error"),
      call  = call
    )
  }
  invisible(name)
}

#' Validate a relative file name inside a raw connection
#'
#' `/` separates sub-folders. Rejected: `..` and `.` segments, absolute paths,
#' drive letters, backslashes, segments that are only dots/spaces or end in a
#' dot or space (Windows strips those, which would bypass the other checks),
#' and control characters.
#'
#' @inheritParams .check_pin_name
#' @return `name`, invisibly.
#' @keywords internal
#' @noRd
.check_rel_name <- function(name, arg = rlang::caller_arg(name),
                            call = rlang::caller_env()) {
  .check_name_scalar(name, arg = arg, call = call)
  bad <- grepl("\\\\", name, useBytes = TRUE) ||          # backslash
    grepl("^/", name) || grepl("^[A-Za-z]:", name) ||     # absolute / drive letter
    grepl("(^|/)\\.\\.(/|$)", name) ||                    # ".." segment
    grepl("(^|/)\\.(/|$)", name) ||                       # "." segment
    grepl("(^|/)[. ]+(/|$)", name) ||                     # dot/space-only segment
    grepl("[. ](/|$)", name) ||                           # trailing dot/space
    grepl("[[:cntrl:]]", name, useBytes = TRUE)
  if (bad) {
    cli::cli_abort(
      c(
        "{.arg {arg}} is not a valid relative file name: {.val {name}}.",
        i = paste(
          "Use a relative path with {.val /} separators; no {.val ..} or",
          "{.val .} segments, no absolute path, no backslash, no segment",
          "ending in a dot or space, no control characters."
        )
      ),
      class = c("gdpins_error_invalid_name", "gdpins_error"),
      call  = call
    )
  }
  invisible(name)
}

#' Check that a joined local path stays inside its root
#'
#' @param local_dest Character scalar. The joined path.
#' @param local_path Character scalar. The root it must stay under.
#' @param call Environment of the caller, shown in the error.
#'
#' @return The normalised absolute `local_dest`, invisibly.
#' @keywords internal
#' @noRd
.check_local_dest <- function(local_dest, local_path, call = rlang::caller_env()) {
  dest <- fs::path_norm(fs::path_abs(local_dest))
  root <- fs::path_norm(fs::path_abs(local_path))
  if (!fs::path_has_parent(dest, root)) {
    cli::cli_abort(
      "Refusing to write {.path {local_dest}}: it resolves outside {.path {local_path}}.",
      class = c("gdpins_error_path_escape", "gdpins_error"),
      call  = call
    )
  }
  invisible(dest)
}

# Shared scalar branch. The message text is matched by existing tests.
.check_name_scalar <- function(name, arg, call) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    cli::cli_abort(
      "{.arg {arg}} must be a non-empty character scalar.",
      class = c("gdpins_error_invalid_name", "gdpins_error"),
      call  = call
    )
  }
  invisible(name)
}

# Drop names that fail `check` (a validator above), warning once about them.
# Used for names that come from a Drive or board listing, where one hostile
# name must not abort the whole loop.
.drop_invalid_names <- function(names, check, what = "name") {
  ok <- vapply(names, function(n) {
    tryCatch({
      check(n)
      TRUE
    }, gdpins_error_invalid_name = function(e) FALSE)
  }, logical(1L), USE.NAMES = FALSE)
  if (!all(ok)) {
    bad <- names[!ok]
    cli::cli_warn(
      c(
        "!" = "Skipping {length(bad)} {what}{?s} that cannot be stored safely: {.val {bad}}.",
        i = "Rename or remove these items at the source."
      ),
      class = c("gdpins_warning_invalid_name", "gdpins_warning")
    )
  }
  names[ok]
}
