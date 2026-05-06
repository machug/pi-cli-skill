#!/usr/bin/env bash
# /pi resume — continue last Pi session.
# With no args: interactive resume.
# With args: one-shot continue with new prompt.
set -e

if [ $# -eq 0 ]; then
  exec pi -c
else
  exec pi -c -p "$*"
fi
