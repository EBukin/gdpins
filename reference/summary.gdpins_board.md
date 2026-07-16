# Summarise a gdpins_board object

Prints a compact summary (one row per board component) to the console.
Never connects a lazy board — components are listed from the declared
config. See
[lazy-boards](https://ebukin.github.io/gdpins/reference/lazy-boards.md).

## Usage

``` r
# S3 method for class 'gdpins_board'
summary(object, ...)
```

## Arguments

- object:

  A `gdpins_board` object.

- ...:

  Unused.

## Value

Invisibly `object`.
