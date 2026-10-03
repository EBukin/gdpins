#!/bin/sh
# Claude Code PreToolUse hook (Bash and PowerShell tools), wired in
# .claude/settings.json for `git *` and `gh *` commands.
#
# Blocks a command that writes a commit message or text to GitHub
# (git commit; gh pr / issue / release / api) when that text carries
#   - a Co-Authored-By line,
#   - a "Generated with <AI tool>" attribution line, or
#   - any email address (an --author email included, on purpose),
# and tells Claude to write different text. Exit 2 blocks the call; stderr
# goes back to Claude as the reason.
#
# Reads the hook JSON on stdin; needs only sh and grep. If the command names a
# message or body file (--body-file, --notes-file, --file, -F path) that file
# is scanned too, best effort: unquoted paths only, resolved against the
# current directory and then the project directory.
input=$(cat)

if ! printf '%s' "$input" | grep -Eq 'git commit|(^|[^A-Za-z0-9_./-])gh (pr|issue|release|api) '; then
  exit 0
fi

email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
attrib='generated with \[?(claude|copilot|codex|cursor|gemini|chatgpt|gpt|openai|anthropic)'

text=$input
for opt in --body-file --notes-file --file -F; do
  path=$(printf '%s' "$input" | grep -Eo -- "$opt[= ]+[^ \"'\\]+" | head -n 1 | sed -E "s/^$opt[= ]+//")
  [ -n "$path" ] || continue
  for candidate in "$path" "${CLAUDE_PROJECT_DIR:-.}/$path"; do
    if [ -f "$candidate" ]; then
      text="$text
$(cat "$candidate")"
      break
    fi
  done
done

found=""
if printf '%s' "$text" | grep -qi 'co-authored-by'; then
  found="a Co-Authored-By line"
elif printf '%s' "$text" | grep -Eqi "$attrib"; then
  found="an AI attribution line ($(printf '%s' "$text" | grep -Eoi "$attrib" | head -n 1))"
elif printf '%s' "$text" | grep -Eqi "$email"; then
  found="an email address ($(printf '%s' "$text" | grep -Eoi "$email" | head -n 1))"
fi
[ -z "$found" ] && exit 0

cat >&2 <<EOF
Blocked: this command contains $found. Commit messages, pull request text and
anything else this project sends to GitHub carry no email addresses and no AI
attribution.
Write different text that has no email address and no co-author, attribution,
or "generated with" statement crediting Claude Code, Copilot, GPT, or any other
AI tool, then run the command again.
EOF
exit 2
