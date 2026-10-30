#!/usr/bin/env bash
# Outils du TP en conteneurs, sans montage du socket Docker.
set -euo pipefail
cd "$(dirname "$0")"
source ../registry/registry-api.sh
[[ $# -ge 1 ]] || { echo "Usage : $0 syft|trivy|cosign|crane [ARGUMENTS...]" >&2; exit 2; }
tool="$1"
shift
case "$tool" in
    syft) image='anchore/syft@sha256:4cc92b64ca74ffca4c94d4c8fcc01f217731375300be14d0b6eeb2e82eaa110a' ;;
    trivy) image='aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c' ;;
    cosign) image='ghcr.io/sigstore/cosign/cosign@sha256:68839b7f13dac5a6744a5d8818e984dd39183374e37855c19e14d623d9bc9037' ;;
    crane) image='gcr.io/go-containerregistry/crane@sha256:fc86bcad43a000c2a1ca926a1e167db26c053cebc3fa5d14285c72773fb8c11d' ;;
    *) echo "Outil inconnu : $tool" >&2; exit 2 ;;
esac
[[ "$REGISTRY_URL" == https://registry.local:5000 ]] || {
    echo "Ce lanceur utilise la stack locale du TP." >&2; exit 2;
}
artifact_dir="${TP03_ARTIFACT_DIR:-$PWD/../../artifacts/step4}"
mkdir -p "$artifact_dir" keys
out_dir=$(cd "$artifact_dir" && pwd)
key_dir="$PWD/keys"
options=(--rm -i --volume "$out_dir:/out" --workdir /out)
if [[ "${TP03_LOCAL_ONLY:-0}" != 1 ]]; then
    gateway=$(docker compose -f ../registry/compose.yml ps -q gateway)
    [[ -n "$gateway" ]] || { echo "La gateway doit être démarrée." >&2; exit 1; }
    gateway_ip=$(docker inspect --format '{{with index .NetworkSettings.Networks "tp03-registry_default"}}{{.IPAddress}}{{end}}' "$gateway")
    [[ -n "$gateway_ip" ]] || { echo "Réseau du TP absent." >&2; exit 1; }
    ca_file="$(cd "$(dirname "$REGISTRY_CA")" && pwd)/$(basename "$REGISTRY_CA")"
    umask 077
    auth_dir=$(mktemp -d /tmp/tp03-supply-auth.XXXXXX)
    cleanup() { rm -f "$auth_dir/config.json"; rmdir "$auth_dir"; }
    trap cleanup EXIT
    jq -n --arg user "$REGISTRY_USER" --arg password "$REGISTRY_PASSWORD" \
        '{auths: {"registry.local:5000": {auth: (($user + ":" + $password) | @base64)}}}' > "$auth_dir/config.json"
    options+=(--network tp03-registry_default --add-host "registry.local:$gateway_ip"
        --env DOCKER_CONFIG=/auth --env SSL_CERT_DIR=/etc/ssl/certs:/certs
        --volume "$auth_dir:/auth:ro" --volume "$ca_file:/certs/ca.crt:ro")
fi
case "$tool" in
    syft) options+=(--env SYFT_CHECK_FOR_APP_UPDATE=false --env SYFT_REGISTRY_CA_CERT=/certs/ca.crt) ;;
    trivy) options+=(--volume tp03-trivy-cache:/cache --env TRIVY_CACHE_DIR=/cache) ;;
    cosign) options+=(--user "$(id -u):$(id -g)" --volume "$key_dir:/keys"
        --env TUF_ROOT=/tmp/tp03-tuf --env "COSIGN_PASSWORD=${COSIGN_PASSWORD:-}") ;;
esac
docker run "${options[@]}" "$image" "$@"
