#!/usr/bin/env bash
#
# Fetches the latest stable and beta Flutter releases from the official
# release index and rewrites versions.json. Intended to be invoked from
# the "Check Flutter versions" GitHub Actions workflow, but safe to run
# locally as well (requires curl and jq).

set -euo pipefail

VERSIONS_FILE="${VERSIONS_FILE:-versions.json}"
RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"

releases_json=$(curl -fsSL "$RELEASES_URL")

get_latest_version_in_channel() {
    local channel=$1
    local channel_hash
    channel_hash=$(jq -r --arg c "$channel" '.current_release[$c] // empty' <<<"$releases_json")
    if [ -z "$channel_hash" ]; then
        echo "Error: channel '$channel' not present in releases index" >&2
        return 1
    fi

    local version
    version=$(jq -r --arg h "$channel_hash" \
        '.releases[] | select(.hash == $h) | .version' <<<"$releases_json")

    if [ -z "$version" ]; then
        echo "Error: no release entry for channel '$channel' (hash $channel_hash)" >&2
        return 1
    fi

    printf '%s' "$version"
}

stable_version=$(get_latest_version_in_channel "stable")
beta_version=$(get_latest_version_in_channel "beta")

echo "Latest stable version: $stable_version"
echo "Latest beta version:   $beta_version"

tmp=$(mktemp)
jq \
    --arg stable "$stable_version" \
    --arg beta   "$beta_version" \
    '{
        images: [
            { flutter_version: $stable, tags: ["latest", "stable"] },
            { flutter_version: $beta,   tags: ["beta"] }
        ]
    }' "$VERSIONS_FILE" >"$tmp"

mv "$tmp" "$VERSIONS_FILE"
