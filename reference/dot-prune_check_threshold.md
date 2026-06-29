# Confirm a bulk removal when threshold is exceeded

In interactive sessions, prompts the user. Non-interactively (or if the
user declines), calls
[`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html).

## Usage

``` r
.prune_check_threshold(n_remove, threshold, context)
```

## Arguments

- n_remove:

  Integer. Number of versions that would be removed.

- threshold:

  Integer. Configured removal threshold.

- context:

  Character scalar. Context description shown in the prompt (e.g.
  `"pin 'mypin'"` or `"board 'test' across 3 pins"`).
