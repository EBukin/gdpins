# Extract a field from a gdpins_board

Connects a lazy board on first read of `drive_board`, `cache_board`, or
`local_board`; every other field is answered without connecting. See
[lazy-boards](https://ebukin.github.io/gdpins/reference/lazy-boards.md).

## Usage

``` r
# S3 method for class 'gdpins_board'
x$name

# S3 method for class 'gdpins_board'
x[[i, ...]]
```

## Arguments

- x:

  A `gdpins_board` object.

- name, i:

  Character scalar. Field name.

- ...:

  Unused.

## Value

The field value, or `NULL` if there is no such field.

## Details

Unlike `$` on a plain list, these do **not** partial-match:
`board$drive` is `NULL`, not `board$drive_board`.
