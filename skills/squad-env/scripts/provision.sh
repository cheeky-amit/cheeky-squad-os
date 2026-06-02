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
    "") return 1 ;;                 # empty → no sandbox declared
  esac
  return 0
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

  NAME=$(printf '%s' "$ROLE_JSON" | jq -r '.name // empty')
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

  # --- Dimension 1: filesystem workspace ------------------------------------
  mkdir -p "$WS" "$WS/bin"
  DIRS_MADE=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    # Sub-dirs are joined under the workspace; reject any "/" escape attempt.
    case "$d" in /*|..|../*|*/..|*/../*) continue ;; esac
    mkdir -p "$WS/$d"
    DIRS_MADE=$((DIRS_MADE + 1))
  done < <(printf '%s' "$ROLE_JSON" | jq -r '.environment.dirs[]? // empty')

  # --- Dimension 4: runtime config (the sourced env file) -------------------
  # Written, never exported globally. Roles source it with:
  #   set -a; . <workspace>/env; set +a; <command>
  WS_ABS="$PROJECT_ABS/$WS"
  {
    echo "# cheeky-squad-os role environment for '$NAME' — SOURCE, do not run."
    echo "# Usage: set -a; . \"$WS/env\"; set +a; <your command>"
    echo "PATH=\"$WS_ABS/bin:\$PATH\""
    printf '%s' "$ROLE_JSON" \
      | jq -r '.environment.env // {} | to_entries[] | "\(.key)=\(.value)"'
  } > "$WS/env"

  # --- Dimension 3: context seeding (local copy/link only) ------------------
  CTX_SEEDED=0
  CTX_COUNT=$(printf '%s' "$ROLE_JSON" | jq -r '.environment.context | length // 0' 2>/dev/null || echo 0)
  i=0
  while [ "$i" -lt "${CTX_COUNT:-0}" ]; do
    FROM=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].from // empty")
    INTO=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].into // empty")
    KIND=$(printf '%s' "$ROLE_JSON" | jq -r ".environment.context[$i].kind // \"copy\"")
    i=$((i + 1))
    [ -z "$FROM" ] && continue
    # The destination must stay inside the sandbox.
    case "$INTO" in /*|..|../*|*/..|*/../*) continue ;; esac
    DEST="$WS/${INTO:-.}"
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

    # Default verification: is the named tool on PATH?
    [ -z "$TVERIFY" ] && TVERIFY="command -v $TNAME"

    # shellcheck disable=SC1091  # ./env is a generated, role-local file
    if ( cd "$WS" && set -a && . ./env 2>/dev/null && set +a && bash -c "$TVERIFY" ) >/dev/null 2>&1; then
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
  jq -n \
    --arg ws "$WS" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson dirs "$DIRS_MADE" --argjson ctx "$CTX_SEEDED" \
    --argjson ready "$TOOLS_READY" --argjson installed "$TOOLS_INSTALLED" \
    --argjson needs "$ROLE_NEEDS" \
    '{workspace:$ws,provisioned_at:$ts,dirs:$dirs,context:$ctx,tools_ready:$ready,tools_installed:$installed,needs:$needs}' \
    > "$WS/.provisioned.json" 2>/dev/null || true

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
