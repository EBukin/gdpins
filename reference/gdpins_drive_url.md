# Return the Google Drive URL for a folder

Returns the browser URL for the Drive folder at `path` (relative to the
adapter root). Useful for visually verifying folder locations before
setting up boards.

## Usage

``` r
gdpins_drive_url(adapter, path = "")
```

## Arguments

- adapter:

  A `gdpins_drive_adapter` object.

- path:

  Character scalar. Path relative to the adapter root. Default `""`
  returns the URL for the root folder itself.

## Value

Character scalar URL, or `NA_character_` for fake adapters.

## Details

For fake adapters (test seams), returns `NA_character_` and emits an
informative message.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
to create a real adapter.

## Examples

``` r
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
gdpins_drive_url(adapter)             # root folder URL
gdpins_drive_url(adapter, "data-raw") # subfolder URL
} # }
```
