#!/usr/bin/env bash
# Fonctions partagées : HTTP avec curl, traitement JSON avec jq.
REGISTRY_URL="${REGISTRY_URL:-https://registry.local:5000}"
REGISTRY_URL="${REGISTRY_URL%/}"
REGISTRY_USER="${REGISTRY_USER:-ci}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-${CI_PASSWORD:-ci-push-2024}}"
REGISTRY_CA="${REGISTRY_CA:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/certs/ca.crt}"
REGISTRY_PAGE_SIZE="${REGISTRY_PAGE_SIZE:-100}"
MANIFEST_ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

registry_curl() {
    local routing=(--connect-timeout 10)
    # La stack du TP publie uniquement sur loopback. Éviter le délai mDNS de .local.
    if [[ "$REGISTRY_URL" == https://registry.local:5000 ]]; then
        routing+=(--resolve registry.local:5000:127.0.0.1)
    fi
    curl --silent --show-error --fail --noproxy '*' "${routing[@]}" --max-time 60 \
        --cacert "$REGISTRY_CA" --user "$REGISTRY_USER:$REGISTRY_PASSWORD" "$@"
}

registry_repo() {
    [[ "$1" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$ ]] || {
        echo "Nom de dépôt invalide : $1" >&2; return 1;
    }
}

registry_list() {
    local path="$1" field="$2" page items='[]' last='' next query response
    [[ "$REGISTRY_PAGE_SIZE" =~ ^[1-9][0-9]*$ ]] || return 1
    while :; do
        query="n=$REGISTRY_PAGE_SIZE"
        if [[ -n "$last" ]]; then
            query="$query&last=$(jq -nr --arg value "$last" '$value | @uri')"
        fi
        response=$(registry_curl --include "$REGISTRY_URL/v2/$path?$query") || return
        page=$(jq -Rrsc --arg field "$field" \
            '(split("\r\n\r\n") | last | fromjson | .[$field] // []) | if type == "array" then . else error("Liste invalide") end' <<< "$response") || return
        [[ "$page" != '[]' ]] || break
        items=$(jq -cn --argjson all "$items" --argjson page "$page" '$all + $page')
        # L'absence de Link annonce la dernière page, même si elle est pleine.
        jq -Rse 'test("(?im)^Link:.*rel=\\\"?next")' >/dev/null <<< "$response" || break
        next=$(jq -r 'last' <<< "$page")
        [[ "$next" != "$last" ]] || { echo "Pagination bloquée." >&2; return 1; }
        last="$next"
    done
    jq -c 'unique' <<< "$items"
}

registry_tags() {
    registry_repo "$1" || return
    registry_list "$1/tags/list" tags
}

registry_digest() {
    local repository="$1" reference="$2"
    registry_repo "$repository" || return
    [[ "$reference" =~ ^[A-Za-z0-9_][A-Za-z0-9_.:-]*$ ]] || return 1
    registry_curl --head --header "Accept: $MANIFEST_ACCEPT" \
        "$REGISTRY_URL/v2/$repository/manifests/$reference" |
        jq -Rrs '[split("\n")[] | capture("(?i)^Docker-Content-Digest:\\s*(?<digest>sha256:[a-f0-9]{64})\\s*$") | .digest] | last // error("Digest absent du HEAD")' -r
}

registry_manifest() {
    registry_curl --header "Accept: $MANIFEST_ACCEPT" \
        "$REGISTRY_URL/v2/$1/manifests/$2"
}

registry_delete() {
    registry_repo "$1" || return
    [[ "$2" =~ ^sha256:[a-f0-9]{64}$ ]] || {
        echo "Suppression uniquement par digest sha256 complet." >&2; return 1;
    }
    local status
    status=$(registry_curl --request DELETE --output /dev/null --write-out '%{http_code}' \
        "$REGISTRY_URL/v2/$1/manifests/$2") || return
    [[ "$status" == 202 ]] || { echo "DELETE inattendu : HTTP $status" >&2; return 1; }
    echo "Supprimé : $1@$2 (HTTP $status)" >&2
}
