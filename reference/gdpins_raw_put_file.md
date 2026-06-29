# Upload a file verbatim to a raw connection

Copies a local file byte-for-byte to Drive and mirrors locally. No R
round-trip, no coercion — byte-faithful upload.

## Usage

``` r
gdpins_raw_put_file(conn, path, name)
```

## Arguments

- conn:

  A `gdpins_raw_conn` object.

- path:

  Character scalar. Path to the local source file.

- name:

  Character scalar. Relative destination path within the raw-root.

## Value

Invisibly `NULL`.
