#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh
#
# Tags look like `v<NetBox version>-<release>`, where the NetBox version is the
# compound tag this role pins - the NetBox version and the netbox-docker
# version joined together - so a full tag reads `v4.6.8-5.0.2-0`:
#
# - if defaults/main.yml points at a version that has never been released, the
#   release counter restarts at 0 (`v4.6.8-5.0.2-0`)
# - otherwise the counter is incremented (`v4.6.8-5.0.2-1`), but only if
#   something that actually affects the role has changed since the last release
#
# Determining the version from defaults/main.yml, rather than from the commit
# message of the pull request that got merged, makes the result independent of
# the order in which pull requests get merged, and lets any change to the role
# (bugfix, feature, dependency bump) release itself without a human tagging.

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

defaults_path='defaults/main.yml'

# Paths that shape the behavior of the role for its consumers. A commit
# touching only other paths (a README fix, CI configuration, Molecule tests)
# does not change what a playbook run does, and releasing it would only create
# churn in the repositories that consume this role.
role_defining_paths=(
	'defaults'
	'meta'
	'tasks'
	'templates'
)

version="$(sed -nE 's|^netbox_version:[[:space:]]*"?([^"[:space:]]+)"?.*$|\1|p' "$defaults_path" | head -n1)"

if [ -z "$version" ]; then
	echo >&2 "Could not determine the NetBox version from $defaults_path"
	exit 1
fi

# The version values already carry a leading `v` (e.g. `v4.6.8-5.0.2`),
# which must not be doubled in the tag.
tag_prefix="v${version#v}-"

# Of all releases of this version, the highest release number.
#
# The `^[0-9]+$` filter is load-bearing rather than defensive: this repository
# has released both bare NetBox versions and compound ones, so the tag list
# holds `v4.5.1-0` alongside `v4.5.1-4.0.0-0`. A bare `v4.5.1` pin makes the
# prefix `v4.5.1-`, which both of those match - and only one of them is this
# version's release counter. Sorted numerically, so that -10 is recognized as
# newer than -9.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

if git diff --quiet "$previous_tag" HEAD -- "${role_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the role has changed since $previous_tag"
	exit 0
fi

echo >&2 "The role has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
