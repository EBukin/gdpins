# Emit a compact key-value line via cli

Formats each `name = value` pair as a `cli`-styled bullet:
` {.field name}: {.val value}`. Truncates long values to keep lines
\<=80 characters. Passes `...` as named arguments where names become
keys and values become the displayed values.

## Usage

``` r
gd_cli_kv(...)
```

## Arguments

- ...:

  Named arguments. Names are the keys; values are coerced to character
  for display.

## Value

Invisibly `NULL`. Called for its side effect of printing.
