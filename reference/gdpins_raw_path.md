# Resolve a raw file to its absolute local path

Given either a relative path within the raw-root (e.g. `"sub/data.csv"`)
or a Google Drive file ID, returns the absolute local filesystem path to
the file, downloading it from Drive if it is not already present
locally.

## Usage

``` r
gdpins_raw_path(conn, name_or_id)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object created by
  [`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md).

- name_or_id:

  Character scalar. Either:

  Relative path

  :   A path within the raw-root, using `"/"` as separator (e.g.
      `"api/gdp_2024.parquet"` or `"my data (2024).csv"`).

  Drive file ID

  :   A Google Drive file ID (≥ 25 alphanumeric characters, no slashes
      or hyphens). Only supported with a real adapter.

## Value

Character scalar. Absolute local filesystem path to the file. The file
is guaranteed to exist when a non-error value is returned.

## Details

Files that already exist in the local mirror are **never**
re-downloaded. Call
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
with `force_refresh = TRUE` if you need to guarantee freshness.

**Resolution order:**

1.  If `name_or_id` looks like a Drive ID (≥ 25 purely alphanumeric
    chars):

    - Errors on local-only connections (no Drive adapter).

    - Errors on fake-adapter connections (fake adapter has no real IDs).

    - On real adapters: fetches file metadata via
      [`googledrive::drive_get()`](https://googledrive.tidyverse.org/reference/drive_get.html),
      downloads to `conn$local_path/<filename>`, and returns the path.

2.  Otherwise treated as a relative path:

    - Returns the local path immediately if the file already exists.

    - Downloads from Drive if not present (drive-backed connections
      only).

    - Errors if local-only and the file is missing.

## See also

[`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md)
to list files and obtain their paths,
[`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
to read a file as an R object,
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
to create a connection.

## Examples

``` r
adapter <- gdpins_fake_drive()
conn <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = tempfile("raw_"),
  adapter    = adapter,
  create     = TRUE
)
gdpins_raw_put_object(conn, mtcars, "cars.csv")

# Already local — returns path immediately, no download
path <- gdpins_raw_path(conn, "cars.csv")
file.exists(path)   # TRUE
#> [1] TRUE
read.csv(path)      # read directly with base R
#>     mpg cyl  disp  hp drat    wt  qsec vs am gear carb
#> 1  21.0   6 160.0 110 3.90 2.620 16.46  0  1    4    4
#> 2  21.0   6 160.0 110 3.90 2.875 17.02  0  1    4    4
#> 3  22.8   4 108.0  93 3.85 2.320 18.61  1  1    4    1
#> 4  21.4   6 258.0 110 3.08 3.215 19.44  1  0    3    1
#> 5  18.7   8 360.0 175 3.15 3.440 17.02  0  0    3    2
#> 6  18.1   6 225.0 105 2.76 3.460 20.22  1  0    3    1
#> 7  14.3   8 360.0 245 3.21 3.570 15.84  0  0    3    4
#> 8  24.4   4 146.7  62 3.69 3.190 20.00  1  0    4    2
#> 9  22.8   4 140.8  95 3.92 3.150 22.90  1  0    4    2
#> 10 19.2   6 167.6 123 3.92 3.440 18.30  1  0    4    4
#> 11 17.8   6 167.6 123 3.92 3.440 18.90  1  0    4    4
#> 12 16.4   8 275.8 180 3.07 4.070 17.40  0  0    3    3
#> 13 17.3   8 275.8 180 3.07 3.730 17.60  0  0    3    3
#> 14 15.2   8 275.8 180 3.07 3.780 18.00  0  0    3    3
#> 15 10.4   8 472.0 205 2.93 5.250 17.98  0  0    3    4
#> 16 10.4   8 460.0 215 3.00 5.424 17.82  0  0    3    4
#> 17 14.7   8 440.0 230 3.23 5.345 17.42  0  0    3    4
#> 18 32.4   4  78.7  66 4.08 2.200 19.47  1  1    4    1
#> 19 30.4   4  75.7  52 4.93 1.615 18.52  1  1    4    2
#> 20 33.9   4  71.1  65 4.22 1.835 19.90  1  1    4    1
#> 21 21.5   4 120.1  97 3.70 2.465 20.01  1  0    3    1
#> 22 15.5   8 318.0 150 2.76 3.520 16.87  0  0    3    2
#> 23 15.2   8 304.0 150 3.15 3.435 17.30  0  0    3    2
#> 24 13.3   8 350.0 245 3.73 3.840 15.41  0  0    3    4
#> 25 19.2   8 400.0 175 3.08 3.845 17.05  0  0    3    2
#> 26 27.3   4  79.0  66 4.08 1.935 18.90  1  1    4    1
#> 27 26.0   4 120.3  91 4.43 2.140 16.70  0  1    5    2
#> 28 30.4   4  95.1 113 3.77 1.513 16.90  1  1    5    2
#> 29 15.8   8 351.0 264 4.22 3.170 14.50  0  1    5    4
#> 30 19.7   6 145.0 175 3.62 2.770 15.50  0  1    5    6
#> 31 15.0   8 301.0 335 3.54 3.570 14.60  0  1    5    8
#> 32 21.4   4 121.0 109 4.11 2.780 18.60  1  1    4    2

# Non-standard filenames work too
gdpins_raw_put_object(conn, mtcars, "quarterly report (Q1 2024).csv")
gdpins_raw_path(conn, "quarterly report (Q1 2024).csv")
#> [1] "/tmp/RtmpQ8TPRT/raw_1dfc7036bd22/quarterly report (Q1 2024).csv"

if (FALSE) { # \dontrun{
# Drive ID input — real adapter only
adapter_real <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
conn_real <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = "data/raw/worldbank-api",
  adapter    = adapter_real
)
# Obtain drive_id from gdpins_raw_ls(), then fetch by ID
listing <- gdpins_raw_ls(conn_real)
file_id <- listing$drive_id[listing$name == "gdp_2024.parquet"]
local_path <- gdpins_raw_path(conn_real, file_id)
arrow::read_parquet(local_path)
} # }
```
