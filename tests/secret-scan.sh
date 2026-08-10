#!/usr/bin/env bash
set -euo pipefail

pattern='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{32,}|BEGIN [A-Z ]*PRIVATE KEY'
if git grep -nEI "$pattern" -- . ':!tests/secret-scan.sh'; then
  printf '%s\n' 'secret scan: possible credential material found' >&2
  exit 1
fi
printf '%s\n' 'secret scan: clean'
