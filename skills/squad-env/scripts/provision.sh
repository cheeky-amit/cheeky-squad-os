#!/usr/bin/env bash
# provision.sh — Role-environment provisioner for cheeky-squad-os.
#
# Materializes one sandbox per ACTIVE role that declares an `environment` block
# in .squad/roster.json. A sandbox is a filesystem-and-PATH boundary, NOT a
# kernel jail:
#   - a per-role workspace dir (.squad/workspaces/<role>/) with scaffolded subdirs
#   - a role-local bin/ and a sourced `env` file (never exported globally)
#   - locally-copied/linked reference material (context seeding)
#   - tool readiness verified; local tools optionally installed INTO the sandbox
#
# Anything that cannot be contained inside the sandbox — system packages, MCP
# servers, network fetches, global/experimental flags — is NEVER executed here.
# It is collected into `global_needs` and emitted for the squad-env skill to
# PROPOSE to the user (the documented escape hatch). That is the whole safety
# model: contain what we can, propose what we can't.
#
# Invoked by the squad-env skill (and by squad-spawn before dispatch) via Bash.
# NOT invoked directly by users.
#
# Inputs (positional, in any order with the flag):
#   $1 — path to .squad/roster.json (default: .squad/roster.json relative to CWD)
#   $2 — path to .squad/goal.md     (default: .squad/goal.md relative to CWD)
#   --install — also EXECUTE the install command of each missing kind:"local"
#               tool, into its sandbox. Omit for a dry pass (dirs/env/context +
#               verification + a printed install plan, no installs run).
#
# Outputs (stdout, one JSON object per line — easy for the skill to parse):
#   {"role":"<name>","workspace":"<abs>","dirs":N,"context":M,"tools_ready":R,
#    "tools_installed":I,"needs":[{"name":..,"kind":..,"hint":..}, …],"status":"provisioned"}
#   {"summary":{"roles":N,"global_needs":[…],"local_plan":[…],"errors":K}}
#
# Errors go to stderr. Exit 0 on full success, 1 on any per-role error.

set -euo pipefail

INSTALL=0
POSITIONAL=()
for a in "$@"; do
  if [ "$a" = "--install" ]; then
    INSTALL=1
  else
    POSITIONAL+=("$a")
  fi
done

ROSTER="${POSITIONAL[0]:-.squad/roster.json}"
GOAL="${POSITIONAL[1]:-.squad/goal.md}"

err() { echo "provision.sh: $*" >&2; }

# --- Preflight ---------------------------------------------------------------

if [ ! -f "$GOAL" ]; then
  err "no squad goal at $GOAL — run /cheeky-squad-os:squad-onboard"
  exit 1
fi

if [ ! -f "$ROSTER" ]; then
  err "no roster at $ROSTER — run /cheeky-squad-os:squad-role"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed. Install with: brew install jq (macOS) / apt-get install jq (Linux)"
  exit 1
fi

PROJECT_ABS=$(pwd -P)

# --- Helpers -----------------------------------------------------------------

# A workspace path must be project-relative, with no leading "/" and no ".."
# traversal — the sandbox must live inside the project tree. Returns 0 if safe.
ws_is_safe() {
  local ws="$1"
  case "$ws" in
    /*) return 1 ;;                 # absolute → escapes the project
    ..|../*|*/..|*/../*) return 1 ;; # traversal → escapes the sandbox
    .|./*|*/./*|*//*|*\\*) return 1 ;; # non-normalized or ambiguous
    "") return 1 ;;                 # empty → no sandbox declared
  esac
  return 0
}

# Existing symlink components can redirect a textually safe path outside the
# project. Return success when any component of a project-relative path is a
# symlink so callers can refuse before mkdir, copy, or write follows it.
path_has_symlink() {
  local current="$PROJECT_ABS" rest="$1" segment
  while [ -n "$rest" ]; do
    segment="${rest%%/*}"
    if [ "$segment" = "$rest" ]; then rest=''; else rest="${rest#*/}"; fi
    [ -z "$segment" ] && continue
    current="$current/$segment"
    [ -L "$current" ] && return 0
  done
  return 1
}

# Aggregate accumulators (emitted in the summary line).
GLOBAL_NEEDS="[]"   # JSON array of {role,name,kind,hint}
LOCAL_PLAN="[]"     # JSON array of {role,name,cmd}
ROLE_COUNT=0
ERRORS=0

# --- Per-role provisioning ---------------------------------------------------

# One compact JSON object per active role that declares an environment block.
ROLES_JSON=$(jq -c '.roles[]? | select(.active == true) | select(.environment != null)' "$ROSTER")

if [ -z "$ROLES_JSON" ]; then
  printf '{"summary":{"roles":0,"global_needs":[],"local_plan":[],"errors":0}}\n'
  exit 0
fi

while IFS= read -r ROLE_JSON; do
  [ -z "$ROLE_JSON" ] && continue

  NAME=$(printf '%s' "$ROLE_JSON" | jq -r '.id // .name // empty')
  WS=$(printf '%s' "$ROLE_JSON" | jq -r '.environment.workspace // empty')
  # Strip a single trailing slash for consistent path joins.
  WS="${WS%/}"

  if [ -z "$NAME" ]; then
    err "role with no name in roster — skipping"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  if ! ws_is_safe "$WS"; then
    err "role '$NAME' has unsafe or missing environment.workspace ('$WS') — must be project-relative, no '..' — skipping"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  if path_has_symlink "$WS"; then
    err "role '$NAME' has a symlink component in environment.workspace ('$WS') — skipping"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # --- Dimension 1: filesystem workspace ------------------------------------
  mkdir -p "$WS" "$WS/bin"
  DIRS_MADE=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    # Sub-dirs are joined under the workspace; reject escapes, ambiguous
    # spellings, and existing symlink components before mkdir follows them.
    if ! ws_is_safe "$d" || path_has_symlink "$WS/$d"; then
      err "role '$NAME': unsafe or symlinked environment directory '$d'"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    mkdir -p "$WS/$d"
    DIRS_MADE=$((DIRS_MADE + 1))
  done < <(printf '%s' "$ROLE_JSON" | jq -r '(.environment.directories // .environment.dirs // [])[]? // empty')

  # --- Dimension 4: runtime config (the sourced env file) -------------------
  # Written, never exported globally. Roles source it with:
  #   set -a; . <workspace>/env; set +a; <command>
  WS_ABS="$PROJECT_ABS/$WS"
  VARIABLE_LINES=""
  # Both canonical v2 `variables` and legacy `env` values are untrusted data.
  # Validate names and shell-quote values before writing the sourced env file.
  while IFS= read -r VARIABLE_JSON; do
    [ -z "$VARIABLE_JSON" ] && continue
    VARIABLE_NAME=$(printf '%s' "$VARIABLE_JSON" | jq -r '.key')
    VARIABLE_VALUE=$(printf '%s' "$VARIABLE_JSON" | jq -r '.value')
    [ -z "$VARIABLE_NAME" ] && continue
    case "$VARIABLE_NAME" in
      [A-Za-z_]* ) ;;
      * )
        err "role '$NAME': invalid environment variable name '$VARIABLE_NAME'"
        ERRORS=$((ERRORS + 1))
        continue
        ;;
    esac
    case "$VARIABLE_NAME" in
      *[!A-Za-z0-9_]* )
        err "role '$NAME': invalid environment variable name '$VARIABLE_NAME'"
        ERRORS=$((ERRORS + 1))
        continue
        ;;
    esac
    printf -v VARIABLE_QUOTED '%q' "$VARIABLE_VALUE"
    VARIABLE_LINES="${VARIABLE_LINES}${VARIABLE_NAME}=${VARIABLE_QUOTED}
"
  done < <(printf '%s' "$ROLE_JSON" | jq -c '
    (if .environment.variables != null
     then .environment.variables
     else (.environment.env // {}) end)
    | if type == "object" then to_entries[] else empty end')

  if path_has_symlink "$WS/env"; then
    err "role '$NAME': refusing symlinked environment file '$WS/env'"
    ERRORS=$((ERRORS + 1))
    continue
  else
    {
      echo "# cheeky-squad-os role environment for '$NAME' — SOURCE, do not run."
      echo "# Usage: set -a; . \"$WS/env\"; set +a; <your command>"
      echo "PATH=\"$WS_ABS/bin:\$PATH\""
      printf '%s\n' "$VARIABLE_LINES"
    } > "$WS/env"
  fi

  # --- Dimension 3: context seeding (local copy/link only) ------------------
  CTX_SEEDED=0
  CTX_COUNT=$(printf '%s' "$ROLE_JSON" | jq -r '.environment.context | length // 0' 2>/dev/null || echo 0)
  i=0
  while [ "$i" -lt "${CTX_COUNT:-0}" ]; do
    FROM=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].source // .environment.context[$i].from // empty")
    INTO=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].target // .environment.context[$i].into // empty")
    KIND=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].kind // \"copy\"")
    i=$((i + 1))
    [ -z "$FROM" ] && continue
    # The destination must stay inside the sandbox without following an
    # existing symlink component.
    if [ -z "$INTO" ] || [ "$INTO" = "." ]; then
      DEST="$WS"
    elif ! ws_is_safe "$INTO" || path_has_symlink "$WS/$INTO"; then
      err "role '$NAME': unsafe or symlinked context target '$INTO'"
      ERRORS=$((ERRORS + 1))
      continue
    else
      DEST="$WS/$INTO"
    fi
    case "$KIND" in
      fetch)
        # Network fetch is not containable — defer to the proposal layer.
        GLOBAL_NEEDS=$(printf '%s' "$GLOBAL_NEEDS" \
          | jq -c --arg r "$NAME" --arg n "$FROM" \
              '. += [{role:$r,name:$n,kind:"fetch",hint:("fetch into "+$n)}]')
        continue
        ;;
      link)
        mkdir -p "$DEST"
        # shellcheck disable=SC2086
        if ln -s $FROM "$DEST"/ 2>/dev/null; then CTX_SEEDED=$((CTX_SEEDED + 1)); fi
        ;;
      *)  # copy (default)
        mkdir -p "$DEST"
        # shellcheck disable=SC2086
        if cp -R $FROM "$DEST"/ 2>/dev/null; then CTX_SEEDED=$((CTX_SEEDED + 1)); fi
        ;;
    esac
  done

  # --- Dimension 2: tool readiness ------------------------------------------
  TOOLS_READY=0
  TOOLS_INSTALLED=0
  ROLE_NEEDS="[]"
  TCOUNT=$(printf '%s' "$ROLE_JSON" | jq -r '.environment.tools | length // 0' 2>/dev/null || echo 0)
  t=0
  while [ "$t" -lt "${TCOUNT:-0}" ]; do
    TNAME=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.tools[$t].name // empty")
    TKIND=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.tools[$t].kind // \"system\"")
    TVERIFY=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.tools[$t].verify // empty")
    TINSTALL=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.tools[$t].install // empty")
    t=$((t + 1))
    [ -z "$TNAME" ] && continue

    case "$TNAME" in
      ''|*[!A-Za-z0-9._+-]*)
        err "role '$NAME': invalid tool name '$TNAME'"
        ERRORS=$((ERRORS + 1))
        continue
        ;;
    esac

    # Only two read-only verification forms run during an unconfirmed dry pass:
    # a PATH lookup for a validated token, or a regular-file check for a safe
    # workspace-relative path. All other shell text is a proposal.
    VERIFY_KIND="path"
    VERIFY_VALUE="$TNAME"
    case "$TVERIFY" in
      "") ;;
      "command -v "*)
        VERIFY_VALUE="${TVERIFY#command -v }"
        VERIFY_VALUE="${VERIFY_VALUE#-- }"
        case "$VERIFY_VALUE" in
          ''|*[!A-Za-z0-9._+-]*) VERIFY_KIND="proposal" ;;
        esac
        ;;
      "test -f "*)
        VERIFY_KIND="file"
        VERIFY_VALUE="${TVERIFY#test -f }"
        case "$VERIFY_VALUE" in
          /*|..|../*|*/..|*/../*) VERIFY_KIND="proposal" ;;
        esac
        case "$VERIFY_VALUE" in
          *' '*|*\\*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'`'*|*'$'*|*'('*|*')'*|*'{'*|*'}'*)
            VERIFY_KIND="proposal"
            ;;
        esac
        ;;
      *) VERIFY_KIND="proposal" ;;
    esac

    if [ "$VERIFY_KIND" = "proposal" ]; then
      HINT="verify manually: $TVERIFY"
      ROLE_NEEDS=$(printf '%s' "$ROLE_NEEDS" \
        | jq -c --arg n "$TNAME" --arg h "$HINT" \
            '. += [{name:$n,kind:"verify",hint:$h}]')
      GLOBAL_NEEDS=$(printf '%s' "$GLOBAL_NEEDS" \
        | jq -c --arg r "$NAME" --arg n "$TNAME" --arg h "$HINT" \
            '. += [{role:$r,name:$n,kind:"verify",hint:$h}]')
      continue
    fi

    VERIFY_OK=1
    if [ "$VERIFY_KIND" = "path" ]; then
      # shellcheck disable=SC1091  # ./env is a generated, role-local file
      ( cd "$WS" && set -a && . ./env 2>/dev/null && set +a \
        && command -v -- "$VERIFY_VALUE" ) >/dev/null 2>&1 || VERIFY_OK=0
    else
      ( cd "$WS" && [ -f "$VERIFY_VALUE" ] && [ ! -L "$VERIFY_VALUE" ] ) \
        >/dev/null 2>&1 || VERIFY_OK=0
    fi
    if [ "$VERIFY_OK" -eq 1 ]; then
      TOOLS_READY=$((TOOLS_READY + 1))
      continue
    fi

    # Missing. Containable (local + has install) vs not.
    if [ "$TKIND" = "local" ] && [ -n "$TINSTALL" ]; then
      LOCAL_PLAN=$(printf '%s' "$LOCAL_PLAN" \
        | jq -c --arg r "$NAME" --arg n "$TNAME" --arg c "$TINSTALL" \
            '. += [{role:$r,name:$n,cmd:$c}]')
      if [ "$INSTALL" -eq 1 ]; then
        # Run the install INSIDE the sandbox (cwd = workspace) with the env sourced.
        # shellcheck disable=SC1091  # ./env is a generated, role-local file
        if ( cd "$WS" && set -a && . ./env 2>/dev/null && set +a && bash -c "$TINSTALL" ) >/dev/null 2>&1; then
          TOOLS_INSTALLED=$((TOOLS_INSTALLED + 1))
        else
          err "role '$NAME': local install failed for tool '$TNAME'"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    else
      # System / MCP / flag / no-install → propose to the user, never run here.
      HINT="${TINSTALL:-install $TNAME ($TKIND) yourself}"
      ROLE_NEEDS=$(printf '%s' "$ROLE_NEEDS" \
        | jq -c --arg n "$TNAME" --arg k "$TKIND" --arg h "$HINT" \
            '. += [{name:$n,kind:$k,hint:$h}]')
      GLOBAL_NEEDS=$(printf '%s' "$GLOBAL_NEEDS" \
        | jq -c --arg r "$NAME" --arg n "$TNAME" --arg k "$TKIND" --arg h "$HINT" \
            '. += [{role:$r,name:$n,kind:$k,hint:$h}]')
    fi
  done

  # --- Receipt (idempotency aid for the skill / next run) -------------------
  if path_has_symlink "$WS/.provisioned.json"; then
    err "role '$NAME': refusing symlinked provision receipt '$WS/.provisioned.json'"
    ERRORS=$((ERRORS + 1))
  else
    jq -n \
      --arg ws "$WS" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson dirs "$DIRS_MADE" --argjson ctx "$CTX_SEEDED" \
      --argjson ready "$TOOLS_READY" --argjson installed "$TOOLS_INSTALLED" \
      --argjson needs "$ROLE_NEEDS" \
      '{workspace:$ws,provisioned_at:$ts,dirs:$dirs,context:$ctx,tools_ready:$ready,tools_installed:$installed,needs:$needs}' \
      > "$WS/.provisioned.json" 2>/dev/null || true
  fi

  printf '{"role":"%s","workspace":"%s","dirs":%d,"context":%d,"tools_ready":%d,"tools_installed":%d,"needs":%s,"status":"provisioned"}\n' \
    "$NAME" "$WS_ABS" "$DIRS_MADE" "$CTX_SEEDED" "$TOOLS_READY" "$TOOLS_INSTALLED" "$ROLE_NEEDS"

  ROLE_COUNT=$((ROLE_COUNT + 1))
done <<< "$ROLES_JSON"

# --- Summary -----------------------------------------------------------------

jq -nc \
  --argjson roles "$ROLE_COUNT" \
  --argjson gn "$GLOBAL_NEEDS" \
  --argjson lp "$LOCAL_PLAN" \
  --argjson errs "$ERRORS" \
  '{summary:{roles:$roles,global_needs:$gn,local_plan:$lp,errors:$errs}}'

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0
