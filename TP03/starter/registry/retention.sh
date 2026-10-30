#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/registry-api.sh"

if [[ $# -lt 2 || $# -gt 3 || ! "$2" =~ ^[0-9]+$ || (${3:-} != '' && ${3:-} != --apply) ]]; then
    echo "Usage : $0 DEPOT N [--apply] (aperçu par défaut)" >&2
    exit 2
fi
repository="$1"
keep=$(jq -n --arg value "$2" '$value | tonumber')
registry_repo "$repository"

# Recueillir aussi les manifestes enfants des index multi-architecture.
# Ainsi un ancien tag ne peut pas supprimer l'image d'un index conservé.
manifest_info() {
    local digest="$1" depth="${2:-0}" manifest result child info config created subject
    (( depth < 8 )) || { echo "Index trop profondément imbriqué." >&2; return 1; }
    [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    manifest=$(registry_manifest "$repository" "$digest") || return
    jq -e '.schemaVersion == 2' >/dev/null <<< "$manifest" || return 1
    result=$(jq -cn --arg digest "$digest" --argjson manifest "$manifest" \
        '{digests: [$digest], dates: [], artifact: ($manifest.subject != null or $manifest.artifactType != null)}')
    while IFS= read -r child; do
        [[ -n "$child" ]] || continue
        info=$(manifest_info "$child" "$((depth + 1))") || return
        result=$(jq -cn --argjson a "$result" --argjson b "$info" \
            '$a | .digests += $b.digests | .dates += $b.dates')
    done < <(jq -r '.manifests[]?.digest, .subject.digest? // empty' <<< "$manifest")
    config=$(jq -r 'if .config.mediaType == "application/vnd.oci.image.config.v1+json" or .config.mediaType == "application/vnd.docker.container.image.v1+json" then .config.digest else empty end' <<< "$manifest")
    if [[ -n "$config" ]]; then
        [[ "$config" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
        created=$(registry_curl "$REGISTRY_URL/v2/$repository/blobs/$config" |
            jq -c 'try (.created | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null') || return
        result=$(jq -cn --argjson result "$result" --argjson created "$created" \
            '$result | if $created == null then . else .dates += [$created] end')
    fi
    jq -c '.digests |= unique' <<< "$result"
}

tags=$(registry_tags "$repository")
records='[]'
while IFS= read -r tag; do
    digest=$(registry_digest "$repository" "$tag")
    info=$(manifest_info "$digest")
    records=$(jq -cn --argjson records "$records" --arg tag "$tag" --arg digest "$digest" --argjson info "$info" \
        '$records + [{tag: $tag, digest: $digest, digests: $info.digests, created: ($info.dates | max), artifact: $info.artifact}]')
done < <(jq -r '.[]' <<< "$tags")
plan=$(jq --argjson keep "$keep" -f "$script_dir/retention.jq" <<< "$records")
jq . <<< "$plan"

if [[ ${3:-} != --apply ]]; then
    echo "Aperçu uniquement. Ajouter --apply pour supprimer les digests listés dans delete." >&2
    exit 0
fi

# Vérifier tout le snapshot, y compris les tags protégés, avant la première suppression.
current=$(registry_tags "$repository")
[[ "$current" == "$tags" ]] || { echo "Les tags ont changé : relancer l'aperçu." >&2; exit 1; }
while IFS=$'\t' read -r tag digest; do
    [[ "$(registry_digest "$repository" "$tag")" == "$digest" ]] || {
        echo "Le tag $tag a changé : arrêt sans suppression." >&2; exit 1;
    }
done < <(jq -r '.[] | [.tag, .digest] | @tsv' <<< "$records")
while IFS= read -r digest; do
    registry_delete "$repository" "$digest"
done < <(jq -r '.delete[].digest' <<< "$plan")
echo "Rétention terminée. Lancer garbage-collect.sh pour récupérer les blobs orphelins." >&2
