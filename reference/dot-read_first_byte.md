# Read the first byte of a file

Isolated as its own function so tests can mock the byte-range-lock
failure mode (a read that silently returns 0 bytes) without needing a
real cross-process OS-level lock.

## Usage

``` r
.read_first_byte(path)
```

## Arguments

- path:

  Character scalar. Path to a local file.

## Value

A raw vector of length 0 or 1.
