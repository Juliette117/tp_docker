#!/usr/bin/env bash
# Démonstration SBOM, scans et signature ; la porte de release est l'étape 5.
set -euo pipefail
cd "$(dirname "$0")"
source ../registry/registry-api.sh
mkdir -p ../../artifacts/step4
out=../../artifacts/step4
platform=linux/arm64
image=registry.local:5000/shopapi
tool() { ./tool.sh "$@"; }
cosign_registry() { tool cosign "$1" --registry-cacert /certs/ca.crt "${@:2}"; }

scan() {
    local digest reference code legacy_id
    digest=$(registry_digest shopapi 1.4.2)
    reference="$image@$digest"
    printf '%s\n' "$reference" > "$out/image.txt"
    tool syft "registry:$reference" --platform "$platform" -o spdx-json > "$out/sbom.json.tmp"
    jq -e '.spdxVersion and (.packages | length > 0)' "$out/sbom.json.tmp" >/dev/null
    mv "$out/sbom.json.tmp" "$out/sbom.json"
    jq '.packages | length' "$out/sbom.json" > "$out/package-count.json"
    code=0
    tool trivy image --cacert /certs/ca.crt --image-src remote --platform "$platform" \
        --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 10 \
        --disable-telemetry --timeout 15m --no-progress --format json \
        --output /out/vulnerabilities.json "$reference" || code=$?
    [[ "$code" == 0 || "$code" == 10 ]] || return "$code"
    printf '%s\n' "$code" > "$out/vulnerability-exit-code.txt"

    # Archive locale : pas de publication de legacy ni de socket dans Trivy.
    legacy_id=$(docker image inspect shopapi:legacy --format '{{.Id}}')
    printf '%s\n' "$legacy_id" > "$out/legacy-image-id.txt"
    trap 'rm -f "$out/shopapi-legacy.tar"' EXIT
    docker image save --output "$out/shopapi-legacy.tar" shopapi:legacy
    code=0
    tool trivy image --input /out/shopapi-legacy.tar --scanners secret \
        --image-config-scanners secret --exit-code 10 --disable-telemetry \
        --timeout 15m --no-progress --format json --output /out/secrets-legacy.json || code=$?
    [[ "$code" == 0 || "$code" == 10 ]] || return "$code"
    printf '%s\n' "$code" > "$out/secret-exit-code.txt"
    jq '[.Results[]? | .Target as $target | .Secrets[]? |
        {target: $target, rule: .RuleID, title: .Title, severity: .Severity,
         startLine: .StartLine, endLine: .EndLine}]' \
        "$out/secrets-legacy.json" > "$out/secrets-legacy-summary.json"
    rm -f "$out/shopapi-legacy.tar"
    trap - EXIT
    tool trivy --version > "$out/trivy-version.txt"
    echo "SBOM et scans disponibles dans artifacts/step4 (codes : 0=aucun résultat, 10=détection)."
}

keypair() {
    if [[ -f keys/cosign.key && -f keys/cosign.pub ]]; then return; fi
    [[ ! -e keys/cosign.key && ! -e keys/cosign.pub ]] || {
        echo "Paire de clés incomplète ; ne pas remplacer une clé existante." >&2; return 1;
    }
    tool cosign generate-key-pair --output-key-prefix /keys/cosign
    chmod 600 keys/cosign.key
}

sign() {
    local reference
    reference=$(cat "$out/image.txt")
    keypair
    cosign_registry sign --key /keys/cosign.key --tlog-upload=false --yes "$reference"
    cosign_registry attest --key /keys/cosign.key --tlog-upload=false --yes \
        --type spdxjson --predicate /out/sbom.json "$reference"
}

verify() {
    local reference digest
    reference=$(cat "$out/image.txt")
    digest="${reference##*@sha256:}"
    [[ "$(registry_digest shopapi 1.4.2)" == "sha256:$digest" ]] || {
        echo "Le tag 1.4.2 a changé depuis le scan." >&2; return 1;
    }
    cosign_registry verify --key /keys/cosign.pub --insecure-ignore-tlog \
        "$reference" > "$out/verification.json"
    cosign_registry verify-attestation --key /keys/cosign.pub --insecure-ignore-tlog \
        --type spdxjson "$reference" > "$out/attestation.jsonl"
    jq -s 'map(.payload | @base64d | fromjson)' "$out/attestation.jsonl" > "$out/attestation-payloads.json"
    jq -e --arg digest "$digest" 'length > 0 and all(.[];
        .critical.image["docker-manifest-digest"] == ("sha256:" + $digest))' "$out/verification.json" >/dev/null
    jq -e --arg digest "$digest" --slurpfile sbom "$out/sbom.json" 'any(.[];
        .predicateType == "https://spdx.dev/Document" and
        any(.subject[]; .digest.sha256 == $digest) and .predicate == $sbom[0])' \
        "$out/attestation-payloads.json" >/dev/null
    registry_list _catalog repositories | jq '{repositories: .}' > "$out/catalog.json"
    registry_tags shopapi | jq '{name: "shopapi", tags: .}' > "$out/tags.json"
    echo "OK : signature, digest et contenu du SBOM attesté vérifiés."
}

demo() {
    local reference demo_image before after code
    reference=$(cat "$out/image.txt")
    demo_image=registry.local:5000/tp03-tests/signature
    # Copie de l'image arm64 dans un dépôt réservé à cette expérience.
    tool crane copy --platform "$platform" "$reference" "$demo_image:mutable"
    before=$(registry_digest tp03-tests/signature mutable)
    cosign_registry sign --key /keys/cosign.key --tlog-upload=false --yes "$demo_image@$before"
    cosign_registry verify --key /keys/cosign.pub --insecure-ignore-tlog \
        "$demo_image:mutable" > "$out/demo-before.json"
    tool crane mutate "$demo_image@$before" --label tp03.signature-demo=modified \
        --tag "$demo_image:mutable"
    after=$(registry_digest tp03-tests/signature mutable)
    [[ "$before" != "$after" ]] || { echo "Le digest aurait dû changer." >&2; return 1; }
    code=0
    cosign_registry verify --key /keys/cosign.pub --insecure-ignore-tlog \
        "$demo_image:mutable" > "$out/demo-after.json" 2> "$out/demo-after.log" || code=$?
    [[ "$code" != 0 ]] || { echo "L'image modifiée ne devrait pas être signée." >&2; return 1; }
    # Prouver que le refus n'est pas dû à une panne de la vérification.
    cosign_registry verify --key /keys/cosign.pub --insecure-ignore-tlog \
        "$demo_image@$before" > "$out/demo-original-digest.json"
    jq -n --arg before "$before" --arg after "$after" --argjson code "$code" \
        '{repository: "tp03-tests/signature", tag: "mutable", before: $before,
          after: $after, modifiedTagVerificationExitCode: $code, originalDigestStillVerified: true}' \
        > "$out/tag-mutation.json"
    echo "OK : le tag modifié échoue ; le digest signé d'origine reste vérifiable."
}

case "${1:-all}" in
    scan) scan ;;
    sign) sign ;;
    verify) verify ;;
    demo) demo ;;
    all) scan; sign; verify; demo ;;
    *) echo "Usage : $0 [all|scan|sign|verify|demo]" >&2; exit 2 ;;
esac
