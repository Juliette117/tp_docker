#!/usr/bin/env bash
# Ajoute un tag dans le même dépôt, sans télécharger les couches de l'image.
set -euo pipefail
cd "$(dirname "$0")"
source ./registry-api.sh

if [[ $# != 3 ]]; then
    echo "Usage : $0 DEPOT TAG_OU_DIGEST_SOURCE NOUVEAU_TAG" >&2
    exit 2
fi
repository="$1"
reference="$2"
target="$3"
registry_repo "$repository"
[[ "$REGISTRY_URL" == https://registry.local:5000 ]] || {
    echo "Ce script utilise la stack locale https://registry.local:5000." >&2; exit 2;
}
[[ "$target" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && ${#target} -le 128 && "$target" != latest ]] || {
    echo "Tag cible invalide ou interdit (latest)." >&2; exit 2;
}

# Figer la source par digest avant toute publication.
digest=$(registry_digest "$repository" "$reference")
tags=$(registry_tags "$repository")
if jq -e --arg tag "$target" 'index($tag) != null' >/dev/null <<< "$tags"; then
    existing=$(registry_digest "$repository" "$target")
    [[ "$existing" == "$digest" ]] || {
        echo "Refus : $repository:$target existe avec un autre digest ($existing)." >&2
        exit 1
    }
    echo "Déjà présent : $repository:$target -> $digest (aucune écriture)."
    exit 0
fi

gateway=$(docker compose ps -q gateway)
[[ -n "$gateway" ]] || { echo "La gateway doit être démarrée." >&2; exit 1; }
gateway_ip=$(docker inspect --format '{{with index .NetworkSettings.Networks "tp03-registry_default"}}{{.IPAddress}}{{end}}' "$gateway")
[[ -n "$gateway_ip" ]] || { echo "Réseau tp03-registry_default absent." >&2; exit 1; }
ca_file="$(cd "$(dirname "$REGISTRY_CA")" && pwd)/$(basename "$REGISTRY_CA")"
[[ -f "$ca_file" ]] || { echo "CA absente : $ca_file" >&2; exit 1; }

# Identifiants temporaires, indépendants des connexions Docker personnelles.
umask 077
auth_dir=$(mktemp -d /tmp/tp03-retag.XXXXXX)
cleanup() { rm -f "$auth_dir/config.json"; rmdir "$auth_dir"; }
trap cleanup EXIT
crane_image='gcr.io/go-containerregistry/crane@sha256:fc86bcad43a000c2a1ca926a1e167db26c053cebc3fa5d14285c72773fb8c11d'
crane() {
    docker run --rm -i --network tp03-registry_default \
        --add-host "registry.local:$gateway_ip" \
        --env DOCKER_CONFIG=/auth --env SSL_CERT_FILE=/certs/ca.crt \
        --volume "$auth_dir:/auth" --volume "$ca_file:/certs/ca.crt:ro" \
        "$crane_image" "$@"
}

printf '%s' "$REGISTRY_PASSWORD" |
    crane auth login registry.local:5000 --username "$REGISTRY_USER" --password-stdin
crane tag "registry.local:5000/$repository@$digest" "$target"

actual=$(registry_digest "$repository" "$target")
[[ "$actual" == "$digest" ]] || { echo "Digest cible inattendu : $actual" >&2; exit 1; }
echo "OK : $repository:$target -> $actual"
echo "Retag par crane tag ; aucune couche shopapi téléchargée."
