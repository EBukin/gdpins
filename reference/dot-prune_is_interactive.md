# Thin wrapper around base::interactive() for testability

Isolating the call lets tests mock `.prune_is_interactive()` at the
package level without patching
[`base::interactive`](https://rdrr.io/r/base/interactive.html).

## Usage

``` r
.prune_is_interactive()
```

## Value

Logical scalar.
