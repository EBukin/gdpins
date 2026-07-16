#!/usr/bin/env Rscript
# Fails if a documented, non-internal topic is missing from _pkgdown.yaml's
# reference index -- the same check pkgdown's site build performs, but
# without needing pandoc, so it runs on machines that can't build the site.

if (!requireNamespace("yaml", quietly = TRUE)) {
  cat("yaml package not installed; skipping _pkgdown.yaml index check.\n")
  quit(status = 0)
}

rd_files <- list.files("man", pattern = "\\.Rd$", full.names = TRUE)

topic_info <- function(path) {
  rd <- tools::parse_Rd(path)
  list(
    name     = tools:::.Rd_get_metadata(rd, "name"),
    internal = "internal" %in% tools:::.Rd_get_metadata(rd, "keyword")
  )
}

topics <- lapply(rd_files, topic_info)
public_topics <- vapply(
  Filter(function(x) !x$internal, topics),
  `[[`, character(1), "name"
)

cfg <- yaml::read_yaml("_pkgdown.yaml")
ref <- cfg$reference
if (is.null(ref)) {
  cat("No `reference:` section in _pkgdown.yaml; skipping check.\n")
  quit(status = 0)
}

listed <- trimws(unlist(lapply(ref, function(section) section$contents)))
# Entries using tidyselect-style helpers (e.g. starts_with("x")) can't be
# checked by literal match; skip them rather than false-fail.
literal <- listed[!grepl("(", listed, fixed = TRUE)]

missing <- setdiff(public_topics, literal)

if (length(missing) > 0) {
  cat("_pkgdown.yaml reference index is missing", length(missing), "topic(s):\n")
  cat(paste0("  - ", missing), sep = "\n")
  cat("\nAdd them under `reference:` in _pkgdown.yaml, or mark them\n")
  cat("@keywords internal if they shouldn't appear on the docs site.\n")
  quit(status = 1)
}

cat("_pkgdown.yaml reference index OK (", length(public_topics), "public topics covered).\n")
quit(status = 0)
