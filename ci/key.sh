#!/usr/bin/env bash
# Writes GUTTERTOWN_KEY (PEM, or PEM in base64) to the file given, readable only by the runner user. Never echoes it.
umask 077
if printf '%s' "$GUTTERTOWN_KEY" | grep -q "PRIVATE KEY"; then
  printf '%s\n' "$GUTTERTOWN_KEY" > "$1"
else
  printf '%s' "$GUTTERTOWN_KEY" | base64 --decode > "$1" 2>/dev/null || { echo "key decode failed"; exit 1; }
fi
