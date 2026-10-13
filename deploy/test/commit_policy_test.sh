#!/usr/bin/env bash
# Tests which commits deploy/bin/descon-deploy-backend will take. It extracts
# the script's own ensure_commit_allowed function (so this exercises the
# shipped code, not a copy) and runs it against a throwaway origin + clone.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../bin/descon-deploy-backend"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

die() {
  echo "$*" >&2
  return 1
}
eval "$(sed -n '/^ensure_commit_allowed() {/,/^}/p' "$script")"

git_quiet() { git -c user.name=t -c user.email=t@example.test "$@"; }

# origin: main (c1, c2) and a feature branch (c3 on top of c2)
git init -q --initial-branch=main "$work/origin"
(
  cd "$work/origin" || exit 1
  git_quiet commit -q --allow-empty -m c1
  git_quiet commit -q --allow-empty -m c2
  git checkout -q -b feature
  git_quiet commit -q --allow-empty -m c3
  git checkout -q main
)
git clone -q "$work/origin" "$work/clone"
cd "$work/clone" || exit 1
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*'

main_sha="$(git rev-parse origin/main)"
feature_sha="$(git rev-parse origin/feature)"
# A commit that exists locally but on no branch of origin (an unpushed or
# fork-only commit).
git checkout -q --detach "$main_sha"
git_quiet commit -q --allow-empty -m unpushed
unpushed_sha="$(git rev-parse HEAD)"

expect() { # description, expected exit (0 allow / 1 refuse), policy, sha
  local description="$1" expected="$2" policy="$3" sha="$4" actual=0
  (ensure_commit_allowed "$policy" "$sha") > /dev/null 2>&1 || actual=1
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS  $description"
  else
    echo "  FAIL  $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

echo "default policy (production document): origin/main only"
expect "a commit on main is accepted" 0 main "$main_sha"
expect "a branch-only commit is refused" 1 main "$feature_sha"
expect "an unpushed commit is refused" 1 main "$unpushed_sha"
expect "a SHA that is not in the repository is refused" 1 main "0000000000000000000000000000000000000000"

echo "--any-pushed-commit (preview document): any branch of the repository"
expect "a commit on main is accepted" 0 any "$main_sha"
expect "a branch-only commit is accepted" 0 any "$feature_sha"
expect "an unpushed commit is refused" 1 any "$unpushed_sha"
expect "a SHA that is not in the repository is refused" 1 any "0000000000000000000000000000000000000000"

echo
if [[ "$failures" -eq 0 ]]; then echo "commit policy: all checks passed."; else echo "commit policy: $failures check(s) FAILED."; exit 1; fi
