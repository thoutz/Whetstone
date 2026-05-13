#!/bin/bash
# Auto-sync: stage → commit → push after each Cursor agent session.
# Always exits 0 so a git failure never blocks the session (fail open).

REPO="/Users/tristan/Documents/iOS Project/Whetstone"
GIT="/usr/bin/git"

cd "$REPO" || exit 0

# Stage everything (respects .gitignore)
$GIT add . 2>/dev/null

# Only commit if there is something staged
if $GIT diff --cached --quiet 2>/dev/null; then
  exit 0
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
$GIT commit -m "Auto-sync: $TIMESTAMP" 2>/dev/null || exit 0
$GIT push 2>/dev/null || true

exit 0
