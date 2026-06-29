# Thin wrapper around base::readline() for testability

Isolating the call lets tests mock `.prune_readline()` at the package
level without patching
[`base::readline`](https://rdrr.io/r/base/readline.html).

## Usage

``` r
.prune_readline(prompt)
```

## Arguments

- prompt:

  Character scalar prompt string.

## Value

Character scalar (user input).
