#' Authentication helpers for Google Drive
#'
#' Lazy, CLI-guided authentication using `gargle`/`googledrive`. No auth
#' happens at package load — only when the first Drive operation is attempted.
#'
#' @name auth
NULL

# ── Internal mockable wrappers ────────────────────────────────────────────────

#' @keywords internal
.gd_has_token <- function() googledrive::drive_has_token()

#' @keywords internal
.gd_drive_auth <- function(email = NULL) googledrive::drive_auth(email = email)

#' @keywords internal
.nslookup_googleapis <- function() {
  curl::nslookup("www.googleapis.com", error = FALSE)
}

# ── Exported functions ────────────────────────────────────────────────────────

#' Ensure Google Drive is authenticated
#'
#' Checks whether the current session is authenticated to Google Drive. If not,
#' prints clear `cli` instructions and authenticates using the email address
#' from the `GDRIVE_EMAIL` environment variable. If `email` is empty, falls
#' back to gargle's interactive account selector. The token is cached and reused
#' in subsequent calls.
#'
#' Offline / `"local_only"` work does not require authentication.
#'
#' @param email Character scalar. Google account email. Defaults to
#'   `Sys.getenv("GDRIVE_EMAIL")`. Set `GDRIVE_EMAIL` in your `.Renviron` to
#'   avoid repeated prompts. If empty (`""`), authentication falls back to
#'   gargle's interactive account selector.
#'
#' @return Invisibly `NULL`. Called for its side effect.
#' @export
gdpins_ensure_drive_auth <- function(email = Sys.getenv("GDRIVE_EMAIL")) {
  if (.gd_has_token()) {
    return(invisible(NULL))
  }

  if (nchar(email) == 0L) {
    cli::cli_inform(c(
      "!" = "{.envvar GDRIVE_EMAIL} is not set.",
      " " = "Falling back to interactive account selection.",
      i = paste0(
        "Add {.code GDRIVE_EMAIL=you@example.com} to your ",
        "{.file ~/.Renviron} to avoid interactive prompts."
      )
    ))
    .gd_drive_auth(email = NULL)
    return(invisible(NULL))
  }

  cli::cli_inform(c(
    "i" = "Authenticating to Google Drive as {.val {email}}.",
    " " = "A browser window may open for OAuth consent.",
    " " = paste0(
      "To avoid prompts, set {.envvar GDRIVE_EMAIL} in your ",
      "{.file ~/.Renviron}."
    )
  ))

  .gd_drive_auth(email)
  invisible(NULL)
}

#' Check whether an internet connection is available
#'
#' Returns `TRUE` if the machine can reach the internet (via a DNS lookup of
#' `www.googleapis.com`), `FALSE` otherwise. Used by Drive operations to decide
#' whether to fall back to the local cache.
#'
#' @return Logical scalar.
#' @export
gdpins_is_online <- function() {
  !is.null(.nslookup_googleapis())
}
