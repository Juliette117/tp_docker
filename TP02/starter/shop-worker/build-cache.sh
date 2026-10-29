#!/bin/sh
# Usage : REGISTRY=mon-registre.example.com sh build-cache.sh
set -eu

: "${REGISTRY:?Définir REGISTRY avec une adresse de registre accessible depuis BuildKit}"
BUILDER=${BUILDER:-shop}
VERSION=${VERSION:-1.0}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}
CACHE_REF=${CACHE_REF:-${REGISTRY}/cache:worker}

cd "$(dirname "$0")"
test -f pip.conf || {
    echo "Créer pip.conf à partir de pip.conf.example avant le build." >&2
    exit 1
}

docker buildx build --builder "$BUILDER" \
    --platform "$PLATFORMS" \
    --secret id=pipconf,src=pip.conf \
    --cache-from "type=registry,ref=${CACHE_REF}" \
    --cache-to "type=registry,ref=${CACHE_REF},mode=max" \
    --progress=plain \
    --tag "${REGISTRY}/shop-worker:${VERSION}" \
    --output type=oci,dest=worker.tar .
