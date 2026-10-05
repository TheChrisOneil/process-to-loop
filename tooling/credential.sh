#!/usr/bin/env bash
# Resolve a provider credential into the environment. SOURCE this, do not run it.
#
#   . tooling/credential.sh
#   load_credential GEMINI_API_KEY process-to-loop-gemini || exit 75
#
# The environment wins when it is already set, so CI and a one-off override both
# work. Otherwise the value comes from the macOS login Keychain.
#
# The value is never printed, never written to a file, and never passed as a
# command-line argument — an argument is visible in `ps` to every process on the
# machine. It goes into the environment of this shell and nowhere else.

# load_credential <env-var-name> <keychain-service>
# 0 the variable is set and non-empty. 1 it is not, and why is on stderr.
load_credential() {
  local var=${1:?env var name} svc=${2:?keychain service} val=""

  # Already in the environment: use it and say nothing.
  val=$(eval "printf '%s' \"\${$var-}\"")
  [ -n "$val" ] && return 0

  if ! command -v security >/dev/null 2>&1; then
    echo "REFUSED: $var is not set and this is not macOS, so there is no Keychain to read." >&2
    echo "         Set $var in the environment before running this." >&2
    return 1
  fi

  # The account name. The controller's environment has no USER — it is set by
  # login shells, not by launchd — and this runs under set -u, so "$USER" was a
  # fatal unbound-variable error before the Keychain was ever consulted. It
  # failed in 399ms and reported a locked keychain, which was not the problem.
  local acct
  acct=${USER:-${LOGNAME:-$(id -un 2>/dev/null)}}
  if [ -z "$acct" ]; then
    echo "REFUSED: cannot determine the account name for a Keychain lookup." >&2
    echo "         USER, LOGNAME and id -un are all empty." >&2
    return 1
  fi

  # The agent's security session does not always carry the user's keychain
  # search list: the controller-run check reported "no such item" for a key this
  # shell finds immediately. Name the login keychain explicitly as a fallback
  # rather than trusting the search list to be inherited.
  # NOT $HOME. The agent runs with HOME set to the city directory, so the
  # keychain path resolved under .../cities/ptl-city/Library/Keychains and the
  # search list — which is derived from HOME — found nothing. Resolve the
  # account's real home instead.
  local err kc home
  err=$(mktemp)
  home=$(eval echo "~$acct" 2>/dev/null)
  case "$home" in ~*|"") home=$(dscl . -read "/Users/$acct" NFSHomeDirectory 2>/dev/null | awk '{print $2}') ;; esac
  [ -n "$home" ] || home=$HOME
  kc="$home/Library/Keychains/login.keychain-db"
  if val=$(security find-generic-password -a "$acct" -s "$svc" -w 2>"$err") \
     || { [ -f "$kc" ] && val=$(security find-generic-password -a "$acct" -s "$svc" -w "$kc" 2>"$err"); }; then
    if [ -n "$val" ]; then
      export "$var=$val"
      rm -f "$err"
      return 0
    fi
    echo "REFUSED: Keychain item \"$svc\" exists but holds an empty value." >&2
    rm -f "$err"
    return 1
  fi

  # Distinguish "no such item" from "the keychain would not answer", because the
  # fixes are different and a locked keychain looks like a missing key.
  if grep -q 'could not be found' "$err" 2>/dev/null; then
    echo "REFUSED: no credential. $var is unset and Keychain has no item \"$svc\"." >&2
    # Say where it looked and what security said, or the next failure is as
    # opaque as this one was: the key was present the whole time and the agent's
    # security session simply could not see it.
    echo "         looked as account \"$acct\", service \"$svc\", in the search list and $kc" >&2
    [ -s "$err" ] && { echo "         security said:" >&2; sed 's/^/           /' "$err" >&2; }
    echo "         Store one — the key is typed into the prompt, not the command line:" >&2
    echo "             security add-generic-password -a \"$acct\" -s $svc -w" >&2
  else
    echo "REFUSED: Keychain refused to answer for \"$svc\":" >&2
    sed 's/^/         /' "$err" >&2
    echo "         A locked login keychain reads as a missing key. Unlock it with:" >&2
    echo "             security unlock-keychain" >&2
    echo "         The first headless read also needs \"Always Allow\" once." >&2
  fi
  rm -f "$err"
  return 1
}
