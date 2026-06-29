# Ensure Google Drive is authenticated

Checks whether the current session is authenticated to Google Drive. If
not, prints clear `cli` instructions and authenticates using the email
address from the `GDRIVE_EMAIL` environment variable. If `email` is
empty, falls back to gargle's interactive account selector. The token is
cached and reused in subsequent calls.

## Usage

``` r
gdpins_ensure_drive_auth(email = Sys.getenv("GDRIVE_EMAIL"))
```

## Arguments

- email:

  Character scalar. Google account email. Defaults to
  `Sys.getenv("GDRIVE_EMAIL")`. Set `GDRIVE_EMAIL` in your `.Renviron`
  to avoid repeated prompts. If empty (`""`), authentication falls back
  to gargle's interactive account selector.

## Value

Invisibly `NULL`. Called for its side effect.

## Details

Offline / `"local_only"` work does not require authentication.
