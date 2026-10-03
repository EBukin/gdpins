@AGENTS.md

<!-- caveman-begin -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Answer first: Answer, then reason, then next step.
- Kill ceremony: No greeting, hedging, pleasantries, recap, or closer.
- Short word: "fix" not "implement a solution for".
- Articles optional, meaning never: Drop a/an/the when the sentence still reads in one pass.
- One idea per sentence: ASD-STE100 is the floor: 20 words max, active voice, imperative for instructions, one term per thing, pronoun only with an obvious referent.
- Payload verbatim: Code blocks unchanged.
- Tool runs: bounded status: No text between routine calls.
- User's language: Compress the style, not the language.
- Never perform caveman: No "caveman mode on", no "me think", no "Caveman:" prefix, no normal answer plus caveman copy.

Switch: /caveman (default), /ultracave (fragments, each fact once), /megacave (Classical Chinese 文言文)
Stop: "stop caveman" or "normal mode"

Auto-Clarity: plain prose for security warnings, irreversible actions, step order a fragment could scramble, user confused. Resume after.

Boundaries: code, comments, commits, PRs, docs written normal.
Floor: code, commands, paths, numbers and error strings verbatim; never drop not/never/no/only.
<!-- caveman-end -->

<!-- eb:conversation -->
## How to answer

- Short replies: bullets, no preamble, no recap. Lead with the result.
- Code, commands, paths and error text go in fenced blocks, not in prose.
- One question at a time, and only when the answer changes what you do next. Otherwise state the assumption and proceed.
- Do not narrate what you are about to do or restate what you did. Say what changed and what is left.
<!-- /eb:conversation -->

<!-- eb:docs -->
## Documentation lives in `.docs/` (plans in `tools/`)

Plans follow `AGENTS.md`: `tools/<topic>.md`. `.docs/_templates/plan.md` is a starting point for them.

Two numbered series in `.docs/`, `NNNN-short-name.md`: four digits, next number = highest existing + 1, lowercase words joined by hyphens. Start from the template in `.docs/_templates/`; do not write one from memory.

| Folder | Write one when | It starts with |
|---|---|---|
| `.docs/handoffs/` | a session ends with work unfinished; written for an agent with no context | date, where things stand, how to verify, next steps |
| `.docs/notes/` | the user says "note this" or "record this", or a decision is worth keeping | date, author, one-line summary, then the instruction quoted verbatim |

Quote the user's instruction verbatim in a note before paraphrasing it. Never renumber, rename or delete an existing file in these folders.
<!-- /eb:docs -->

<!-- eb:r -->
## R

- Run R through the `run-r` skill (`mcp__r__repl` and its siblings). It covers the `Rscript` fallback when those tools are missing; do not improvise one.
- An MCP R session may be rooted in another project. Check `getwd()` before `devtools::load_all(".")`; otherwise use `Rscript`.
- When you write or change R code, use Posit's `r-lib` skills, enabled for this project, before your own habits:
  - `r-lib:r-package-development` for package layout, roxygen2 documentation, the devtools and usethis workflow;
  - `r-lib:testing-r-packages` for every test: testthat 3, fixtures, snapshots, mocking;
  - `r-lib:cli` for every user-facing message, error or progress bar (`cli_abort()`, `cli_warn()`, `cli_inform()`, not bare `stop()`, `warning()`, `message()`);
  - `r-lib:lifecycle` when deprecating, renaming or superseding a function or argument;
  - `r-lib:mirai` for parallel or asynchronous R;
  - `r-lib:r-cli-app` when a script becomes a command-line tool;
  - `r-lib:cran-extrachecks`, `r-lib:r-cran-status` and `r-lib:alt-text` for a release, a CRAN check, or figure alt text.
- `R/` holds the package's functions only, one topic per file, roxygen-documented. Load them with `devtools::load_all()`.
- `vignettes/` holds the package vignettes (`.Rmd`). They execute during build and `R CMD check`; keep them runnable.
- The R session's working directory is where Claude Code was started, not the script's folder: build paths from the project root.
<!-- /eb:r -->

<!-- eb:shiny -->
## Shiny

- When you build, style, test or debug a Shiny app, use these skills, enabled for this project, before your own habits:
  - `shiny-dev:shiny-for-r` for reactivity, modules, layout and `testServer` in R; `shiny-dev:shiny-for-python` for the same in py-shiny. Both are Posit's own skills, vendored in eb-ai-skills;
  - `shiny:shiny-bslib` for page layouts, cards, value boxes, sidebars and navigation with bslib, instead of `fluidPage()`, `fluidRow()` or `shinythemes`;
  - `shiny:shiny-bslib-theming` for `bs_theme()`, colours, fonts, dark mode and matching plots with thematic;
  - `shiny:brand-yml` for a `_brand.yml` shared with Quarto documents.
<!-- /eb:shiny -->

<!-- eb:git -->
## Git

- Commit messages and pull-request text carry no email address and no AI attribution: no `Co-Authored-By`, no "Generated with". The hook in `.claude/hooks/no-coauthor.sh` blocks a violation; write different text, never work around it.
- Stage explicit paths, never `git add -A`. Commit only when asked.
<!-- /eb:git -->
