#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Repository files describe what things are, not when or by whom they were
# made: no milestone/task labels (M1-, m2_, T-S3, plan section references)
# and no personal names or handles outside the allow-list (the package
# maintainer identity in debian/ and LICENSE metadata).
#
# Scans tracked files when run inside a git checkout, otherwise every file
# outside build/ and .git/. Vendor sources are third-party and excluded.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ALLOW=$ROOT/tests/static/jargon-allowlist.txt
cd "$ROOT"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	[[ -n $(git ls-files | head -n1) ]]; then
	mapfile -t files < <(git ls-files)
else
	mapfile -t files < <(find . -type f ! -path './build/*' ! -path './.git/*' \
		-printf '%P\n' | sort)
fi

scan=()
for f in "${files[@]}"; do
	case $f in
	vendor/* | tests/static/jargon-allowlist.txt | tests/static/no-session-jargon_test.sh) continue ;;
	esac
	scan+=("$f")
done

# Milestone, task and planning-section labels.
label_re='(^|[^A-Za-z0-9_.])(§[0-9]|[Mm][0-9]+[-_]|T-S[0-9]+)'
# Personal names / handles of contributors that must not appear in prose.
name_re='[Jj]onathan|[Gg]lanz|jglanz'

hits=$(grep -n -I -E "$label_re|$name_re" "${scan[@]}" 2>/dev/null || true)

# Drop allow-listed lines: "<path-glob> <fixed string>" per line.
if [[ -n $hits && -f $ALLOW ]]; then
	while read -r glob fixed; do
		[[ -z $glob || $glob == \#* ]] && continue
		hits=$(printf '%s\n' "$hits" | while IFS= read -r line; do
			file=${line%%:*}
			# shellcheck disable=SC2053
			if [[ $file == $glob && $line == *"$fixed"* ]]; then
				continue
			fi
			printf '%s\n' "$line"
		done)
	done < "$ALLOW"
fi

if [[ -n $hits ]]; then
	echo "no-session-jargon: disallowed labels or names:" >&2
	printf '  %s\n' "$hits" >&2
	exit 1
fi
echo "no-session-jargon: OK (${#scan[@]} files)"
