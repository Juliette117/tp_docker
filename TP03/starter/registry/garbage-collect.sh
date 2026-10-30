#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ $# -gt 1 || (${1:-} != '' && ${1:-} != --apply) ]]; then
    echo "Usage : $0 [--apply] (simulation par défaut)" >&2
    exit 2
fi

restore() {
    local status=$?
    trap - EXIT
    docker compose up -d --wait --wait-timeout 120 registry gateway || {
        echo "Redémarrage incomplet : exécuter docker compose up -d --wait." >&2
        exit 1
    }
    exit "$status"
}

# Aucun serveur de registre ne doit écrire dans le volume pendant le GC.
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker compose stop gateway registry
options=(garbage-collect)
[[ ${1:-} == --apply ]] || options+=(--dry-run)
options+=(/etc/docker/registry/config.yml)
# Ne pas ajouter --delete-untagged : les index référencent des enfants sans tag.
docker compose run --rm --no-deps -T --entrypoint registry registry \
    "${options[@]}"
