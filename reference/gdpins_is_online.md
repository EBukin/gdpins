# Check whether an internet connection is available

Returns `TRUE` if the machine can reach the internet (via a DNS lookup
of `www.googleapis.com`), `FALSE` otherwise. Used by Drive operations to
decide whether to fall back to the local cache.

## Usage

``` r
gdpins_is_online()
```

## Value

Logical scalar.
