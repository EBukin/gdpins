# Version pruning with delete guards

Functions for pruning old pin versions from boards. All Drive removals
use
[`gd_trash()`](https://ebukin.github.io/gdpins/reference/gd_trash.md)
(recoverable; never hard-deletes). Cache removals delete local directory
trees. Raw files are **never** auto-deleted by any function – removal is
manual outside R.
