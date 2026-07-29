#!/usr/bin/env bash
# Lint mermaid sequenceDiagram blocks for the two constructs that silently
# break GitHub's renderer. Both were found live in this repo, both by
# rendering — this check exists so they cannot come back.
#
#   1. ';' inside a sequence message. Mermaid treats ';' as a STATEMENT
#      separator, so the message splits mid-sentence and the remainder is
#      parsed as a bare statement: "Expecting ... arrow ..., got NEWLINE".
#
#   2. '&lt;' / '&gt;' anywhere in a sequenceDiagram block. HTML entities break
#      the sequence parser. This is the exact OPPOSITE of the flowchart rule —
#      in a flowchart node label you MUST escape angle brackets, in a sequence
#      diagram escaping is what breaks it. That asymmetry is why this check
#      exists: the correct flowchart habit, applied one block over, is a bug.
#
# Deliberately structural rather than a real render: CI here is shellcheck +
# bats and finishes in ~25s. Pulling Chromium in to render diagrams would cost
# minutes for a class of bug this catches for free. For a genuine render,
# `npx @mermaid-js/mermaid-cli -i block.mmd -o out.svg` locally.
#
# Usage: mermaid-lint.sh [file ...]   (defaults to every tracked *.md)
set -uo pipefail

fail=0

# Build the file list without `mapfile` — that is bash 4+, and macOS still
# ships bash 3.2. This script has to run on a contributor's laptop, not only
# on CI's Ubuntu.
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  while IFS= read -r _f; do
    [ -n "$_f" ] && files[${#files[@]}]="$_f"
  done <<EOF
$(git ls-files '*.md' 2>/dev/null || find . -name '*.md' -not -path './.git/*')
EOF
fi

# `"${files[@]}"` on an empty array is an unbound-variable error under `set -u`
# in bash 3.2, so guard rather than trip over an empty repo.
[ "${#files[@]}" -eq 0 ] && { echo "mermaid sequence diagrams: no markdown files to check"; exit 0; }

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  in_block=0 is_seq=0 block_start=0 lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))

    if [ "$in_block" -eq 0 ]; then
      case "$line" in
        '```mermaid'*) in_block=1; is_seq=0; block_start=$lineno ;;
      esac
      continue
    fi

    case "$line" in
      '```'*) in_block=0; is_seq=0; continue ;;
    esac

    # First non-blank line of the block declares the diagram type.
    if [ "$is_seq" -eq 0 ] && [ -n "${line// /}" ]; then
      case "${line#"${line%%[![:space:]]*}"}" in
        sequenceDiagram*) is_seq=1 ;;
        *) is_seq=-1 ;;   # some other diagram type — not our business
      esac
      [ "$is_seq" -eq 1 ] && continue
    fi
    [ "$is_seq" -eq 1 ] || continue

    # --- check 1: HTML entities anywhere in a sequence block ---------------
    case "$line" in
      *'&lt;'*|*'&gt;'*)
        echo "::error file=$f,line=$lineno::mermaid sequenceDiagram (opened line $block_start): HTML entity breaks the sequence parser — use a raw < or > here. (Escaping is required in FLOWCHART labels, not in sequence diagrams.)"
        fail=1
        ;;
    esac

    # --- check 2: ';' in a message line ------------------------------------
    # A message line contains an arrow. ';' is a mermaid statement separator,
    # so it truncates the message and derails the parse.
    # ("->" subsumes "-->", "->>" and "-->>" — every arrow form contains it.)
    #
    # Strip HTML entities first: they END in ';' ("&lt;"), so an un-stripped
    # line would trip this check for the wrong reason and report two errors
    # for one defect.
    bare="$line"
    for ent in '&lt;' '&gt;' '&amp;' '&quot;' '&#39;'; do
      bare="${bare//$ent/}"
    done
    case "$line" in
      *'->'*)
        case "$bare" in
          *';'*)
            echo "::error file=$f,line=$lineno::mermaid sequenceDiagram (opened line $block_start): ';' in a message is a statement separator and will break rendering — use a comma or split the message."
            fail=1
            ;;
        esac
        ;;
    esac
  done < "$f"
done

if [ "$fail" -eq 0 ]; then
  echo "mermaid sequence diagrams: clean"
fi
exit "$fail"
