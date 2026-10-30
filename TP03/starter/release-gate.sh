#!/usr/bin/env bash
# IMAGE doit être disponible localement. --push cible le registre TLS du TP.
set -euo pipefail
usage() { echo "Usage : $0 IMAGE [--push registry.local:5000/DEPOT:TAG]" >&2; exit 2; }
[[ $# == 1 || ( $# == 3 && "$2" == --push ) ]] || usage
image="$1"
target="${3:-}"
script_dir=$(cd "$(dirname "$0")" && pwd)
source "$script_dir/registry/registry-api.sh"
if [[ -n "$target" ]]; then
    [[ "$target" == registry.local:5000/*:* && "$target" != *@* ]] || usage
    repository="${target#registry.local:5000/}"
    tag="${repository##*:}"
    repository="${repository%:*}"
    registry_repo "$repository" || usage
    [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && ${#tag} -le 128 && "$tag" != latest ]] || usage
fi

umask 077
mkdir -p "$script_dir/../artifacts/release-gate"
run_dir=$(mktemp -d "$script_dir/../artifacts/release-gate/run.XXXXXX")
export TP03_ARTIFACT_DIR="$run_dir"
status=error
image_id=''
digest=''
container=''
failures=()
finish() {
    local code=$?
    trap - EXIT
    if [[ -n "$container" ]]; then docker container rm "$container" >/dev/null 2>&1 || true; fi
    rm -f "$run_dir/image.tar"
    printf '%s\n' "${failures[@]:-}" | jq -Rsc 'split("\n") | map(select(length > 0))' > "$run_dir/failures.json"
    jq -n --arg status "$status" --arg image "$image" --arg id "$image_id" \
        --arg target "$target" --arg digest "$digest" --argjson code "$code" \
        --slurpfile failures "$run_dir/failures.json" \
        '{status: $status, image: $image, localImageId: $id, target: $target,
          digest: $digest, exitCode: $code, failures: $failures[0]}' > "$run_dir/result.json"
    echo "Rapport : $run_dir/result.json" >&2
    exit "$code"
}
trap finish EXIT
tool_local() { TP03_LOCAL_ONLY=1 "$script_dir/supply-chain/tool.sh" "$@"; }
tool_registry() { TP03_LOCAL_ONLY=0 "$script_dir/supply-chain/tool.sh" "$@"; }
reject() { failures+=("$1"); echo "REFUS : $1" >&2; }

docker image inspect "$image" > "$run_dir/inspect.json"
image_id=$(jq -er '.[0].Id' "$run_dir/inspect.json")
for label in version revision source; do
    if ! jq -e --arg key "org.opencontainers.image.$label" \
        '.[0].Config.Labels[$key] | if type == "string" then test("\\S") else false end' "$run_dir/inspect.json" >/dev/null; then
        reject "Label OCI $label absent ou vide."
    fi
done

user=$(jq -r '.[0].Config.User // "" | split(":")[0]' "$run_dir/inspect.json")
uid="$user"
if [[ -n "$user" && "$user" != root && ! "$user" =~ ^[0-9]+$ ]]; then
    # Lire passwd dans un conteneur arrêté, sans exécuter de code de l'image.
    container=$(docker create --entrypoint /__tp03_never_executed "$image_id")
    if docker cp -L "$container:/etc/passwd" "$run_dir/passwd" 2> "$run_dir/passwd.log"; then
        uid=$(jq -Rrs --arg name "$user" '[split("\n")[] | split(":") |
            select(length >= 4 and .[0] == $name) | .[2]] |
            if length == 1 then .[0] else "" end' "$run_dir/passwd")
    else uid=''; fi
    docker container rm "$container" >/dev/null
    container=''
fi
if [[ ! "$uid" =~ ^[0-9]+$ || "$uid" =~ ^0+$ ]]; then
    reject "Utilisateur root, implicite ou UID non vérifiable."
fi
if ! jq -e '.[0].Config.Healthcheck.Test // [] |
    length >= 2 and (.[0] == "CMD" or .[0] == "CMD-SHELL") and
    (.[1] | if type == "string" then test("\\S") else false end)' "$run_dir/inspect.json" >/dev/null; then
    reject "HEALTHCHECK absent ou désactivé."
fi
if [[ ${#failures[@]} != 0 ]]; then status=rejected; exit 1; fi

# Le tag local peut bouger ensuite : tout le traitement utilise ce snapshot.
docker image save --output "$run_dir/image.tar" "$image_id"
digest=$(tool_local crane digest --tarball /out/image.tar)
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 1
tool_local syft docker-archive:/out/image.tar -o spdx-json > "$run_dir/sbom.json.tmp"
jq -e '(.spdxVersion | type == "string") and (.packages | type == "array")' "$run_dir/sbom.json.tmp" >/dev/null
mv "$run_dir/sbom.json.tmp" "$run_dir/sbom.json"

code=0
tool_local trivy image --input /out/image.tar --config '' --ignorefile '' \
    --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 10 \
    --disable-telemetry --skip-version-check --timeout 15m --no-progress \
    --format json --output /out/vulnerabilities.json || code=$?
case "$code" in
    0) ;;
    10) reject "CVE HIGH/CRITICAL corrigeable détectée." ;;
    *) echo "Erreur d'exécution du scan CVE (code $code)." >&2; exit "$code" ;;
esac
code=0
tool_local trivy image --input /out/image.tar --config '' --ignorefile '' --secret-config '' \
    --scanners secret --image-config-scanners secret --exit-code 10 \
    --disable-telemetry --skip-version-check --timeout 15m --no-progress \
    --format json --output /out/secrets.json || code=$?
case "$code" in
    0) ;;
    10) reject "Secret détecté dans les fichiers ou la configuration d'image." ;;
    *) echo "Erreur d'exécution du scan de secrets (code $code)." >&2; exit "$code" ;;
esac
tool_local trivy --version > "$run_dir/trivy-version.txt"
if [[ ${#failures[@]} != 0 ]]; then status=rejected; exit 1; fi

if [[ -z "$target" ]]; then
    status=accepted
    echo "ACCEPTÉ : métadonnées, utilisateur, HEALTHCHECK, CVE et secrets conformes."
    exit 0
fi
[[ -s "$script_dir/supply-chain/keys/cosign.key" && -s "$script_dir/supply-chain/keys/cosign.pub" ]] || {
    echo "Paire Cosign absente : réaliser l'étape 4 avant publication." >&2; exit 1;
}

# Pas de remplacement silencieux d'un tag. Sérialiser les publications en CI.
http=$(registry_curl --no-fail --head --header "Accept: $MANIFEST_ACCEPT" \
    --output /dev/null --write-out '%{http_code}' "$REGISTRY_URL/v2/$repository/manifests/$tag")
case "$http" in
    200)
        [[ "$(registry_digest "$repository" "$tag")" == "$digest" ]] || {
            reject "Le tag cible existe avec un autre digest."; status=rejected; exit 1;
        } ;;
    404) ;;
    *) echo "Impossible de vérifier la destination (HTTP $http)." >&2; exit 1 ;;
esac
tool_registry crane push /out/image.tar "$target"
[[ "$(registry_digest "$repository" "$tag")" == "$digest" ]] || {
    echo "Le digest publié diffère du snapshot analysé." >&2; exit 1;
}
reference="registry.local:5000/$repository@$digest"
tool_registry cosign sign --registry-cacert /certs/ca.crt --key /keys/cosign.key \
    --tlog-upload=false --yes "$reference"
tool_registry cosign attest --registry-cacert /certs/ca.crt --key /keys/cosign.key \
    --tlog-upload=false --yes --type spdxjson --predicate /out/sbom.json "$reference"
tool_registry cosign verify --registry-cacert /certs/ca.crt --key /keys/cosign.pub \
    --insecure-ignore-tlog "$reference" > "$run_dir/verification.json"
tool_registry cosign verify-attestation --registry-cacert /certs/ca.crt --key /keys/cosign.pub \
    --insecure-ignore-tlog --type spdxjson "$reference" > "$run_dir/attestation.jsonl"
jq -s 'map(.payload | @base64d | fromjson)' "$run_dir/attestation.jsonl" > "$run_dir/attestation-payloads.json"
jq -e --arg digest "$digest" 'length > 0 and all(.[];
    .critical.image["docker-manifest-digest"] == $digest)' "$run_dir/verification.json" >/dev/null
jq -e --arg digest "${digest#sha256:}" --slurpfile sbom "$run_dir/sbom.json" \
    'any(.[]; .predicateType == "https://spdx.dev/Document" and
    any(.subject[]; .digest.sha256 == $digest) and .predicate == $sbom[0])' \
    "$run_dir/attestation-payloads.json" >/dev/null
[[ "$(registry_digest "$repository" "$tag")" == "$digest" ]] || exit 1
status=released
echo "PUBLIÉ, SIGNÉ ET ATTESTÉ : $reference"
