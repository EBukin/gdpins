# Create a real Google Drive adapter

Wraps `googledrive` functions via Drive-ID-based navigation. Supply
either a Google Drive folder ID or a path string to the project root
folder.

## Usage

``` r
gdpins_real_drive(root_id, email = Sys.getenv("GDRIVE_EMAIL"))
```

## Arguments

- root_id:

  Character scalar. Drive folder ID of the project root folder, or a
  Drive path string (for example `"My Drive/projects/myproject"`).

- email:

  Character scalar. Google account email used for authentication.
  Defaults to `Sys.getenv("GDRIVE_EMAIL")`. Set `GDRIVE_EMAIL` in your
  `.Renviron` to avoid repeated prompts. Pass `""` to use gargle's
  interactive account selector.

## Value

An object of class `gdpins_drive_adapter`.

## Details

If `root_id` looks like a Drive path (contains `"/"` or spaces),
`gdpins_real_drive()` resolves it via
[`googledrive::drive_get()`](https://googledrive.tidyverse.org/reference/drive_get.html).
Otherwise it is treated as a Drive folder ID directly.

Authentication is handled automatically:
[`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)
is called when creating the adapter. If a valid token already exists it
is reused. If `email` is non-empty, that account is requested; otherwise
gargle shows interactive account selection.

## See also

[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)

## Examples

``` r
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
adapter

# Path strings are auto-resolved via googledrive::drive_get()
adapter2 <- gdpins_real_drive("My Drive/projects/myproject")
adapter2
} # }
```
