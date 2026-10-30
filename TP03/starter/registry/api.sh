#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/registry-api.sh"

case "${1:-}" in
    catalog)
        [[ $# == 1 ]] || exit 2
        registry_list _catalog repositories | jq '{repositories: .}' ;;
    tags)
        [[ $# == 2 ]] || exit 2
        registry_tags "$2" | jq --arg name "$2" '{name: $name, tags: .}' ;;
    digest)
        [[ $# == 3 ]] || exit 2
        registry_digest "$2" "$3" ;;
    manifest)
        [[ $# == 3 ]] || exit 2
        registry_repo "$2"
        registry_manifest "$2" "$3" | jq . ;;
    delete)
        [[ $# == 3 ]] || exit 2
        registry_delete "$2" "$3" ;;
    *)
        echo "Usage : $0 catalog | tags DEPOT | digest DEPOT TAG | manifest DEPOT REF | delete DEPOT DIGEST" >&2
        exit 2 ;;
esac
