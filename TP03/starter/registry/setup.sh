#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
umask 077

for tool in openssl htpasswd; do
    command -v "$tool" >/dev/null || { echo "Outil requis : $tool" >&2; exit 1; }
done

mkdir -p certs auth
chmod 755 certs auth

if [[ ! -f certs/ca.crt && ! -f certs/ca.key ]]; then
    openssl genrsa -out certs/ca.key 4096
    openssl req -new -x509 -sha256 -days 3650 \
        -key certs/ca.key -out certs/ca.crt \
        -subj "/CN=Shop SAS TP03 CA/O=Shop SAS TP03" \
        -config openssl.cnf -extensions ca_extensions
fi
if [[ ! -f certs/ca.crt || ! -f certs/ca.key ]]; then
    echo "CA incomplète : restaurer certs/ca.crt et certs/ca.key." >&2
    exit 1
fi

if [[ ! -f certs/registry.crt && ! -f certs/registry.key ]]; then
    openssl genrsa -out certs/registry.key 3072
    openssl req -new -sha256 -key certs/registry.key \
        -out certs/registry.csr -config openssl.cnf
    openssl x509 -req -sha256 -days 365 \
        -in certs/registry.csr -CA certs/ca.crt -CAkey certs/ca.key \
        -CAcreateserial -out certs/registry.crt \
        -extfile openssl.cnf -extensions server_extensions
fi
if [[ ! -f certs/registry.crt || ! -f certs/registry.key ]]; then
    echo "Certificat serveur incomplet : restaurer la paire certificat/clé." >&2
    exit 1
fi
openssl verify -CAfile certs/ca.crt certs/registry.crt
chmod 644 certs/ca.crt certs/registry.crt

# Les valeurs par défaut sont les identifiants de démonstration du TP.
# Les variables permettent de les remplacer à la première initialisation.
if [[ ! -f auth/htpasswd ]]; then
    printf '%s\n' "${CI_PASSWORD:-ci-push-2024}" | htpasswd -niB ci > auth/htpasswd
    printf '%s\n' "${DEV_PASSWORD:-dev-pull-2024}" | htpasswd -niB dev >> auth/htpasswd
fi
sed -n '/^ci:/p' auth/htpasswd > auth/ci.htpasswd
if [[ ! -s auth/ci.htpasswd || -z "$(sed -n '/^dev:/p' auth/htpasswd)" ]]; then
    echo "Les comptes ci et dev doivent exister dans auth/htpasswd." >&2
    exit 1
fi
chmod 644 auth/htpasswd auth/ci.htpasswd

if [[ ! -f .env ]]; then
    printf 'REGISTRY_HTTP_SECRET=%s\n' "$(openssl rand -hex 32)" > .env
fi
echo "Préparation terminée. Démarrer avec : docker compose up -d --wait"
