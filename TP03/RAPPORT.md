# Rapport TP03

## 1. Registre sécurisé

Registre avec TLS, comptes bcrypt, volumes persistants, suppression activée,
healthchecks, redémarrage automatique, UI et mirror Docker Hub.
Validé : accès anonyme refusé (401), push avec `ci`, pull avec `dev`,
écritures interdites à `dev`, persistance et utilisation du mirror.

**htpasswd suffit-il en entreprise ?** Il authentifie sans gérer les droits
par dépôt. Nginx sépare ici lecture et écriture. Harbor, Nexus ou les registres
cloud peuvent ajouter RBAC/SSO, scans, réplication, quotas et tags immuables.

## 2. API et rétention

Catalogue, tags, digest par HEAD et suppression réalisés avec curl et jq.
**Supprimer un digest rend inaccessibles tous les tags du même manifeste.**
Le garbage collection, registre arrêté, a supprimé six blobs orphelins.

`retention.sh` conserve les versions SemVer et N autres tags selon la date de
construction, car l'API ne fournit pas la date de push. Signatures et manifestes
partagés sont protégés. Test N=2 : trois tags supprimés, neuf conservés.

## 3. Tags

[TAGGING.md](TAGGING.md) décrit les versions immuables par convention,
l'interdiction de `latest` en production et la référence par digest dans Compose.
Retag avec crane validé : `1.4.2` et `tp03-retag-demo` ont le même digest,
sans téléchargement des couches.

## 4. SBOM, scan et signature

Résultats des scans sur les images initiales, avant
reconstruction de `shopapi:1.4.2` :

| Contrôle | Résultat |
| --- | --- |
| SBOM de `1.4.2` avec Syft | SPDX JSON, 340 composants |
| Trivy sur `1.4.2`, CVE corrigeables | 25 HIGH et 1 CRITICAL |
| Secrets dans `legacy` | Clé AWS détectée dans `/app/.env`, ligne 4 |
| Signature et attestation SBOM | Vérifiées avec une clé locale, sans Rekor |

Cosign crée les tags `sha256-<digest>.sig` et `.att` dans le même dépôt.
**La signature suit le digest :** après modification de l'image sous le même
tag, la vérification échoue ; l'ancien digest signé reste vérifiable.

## 5. Porte de release

`release-gate.sh` refuse les labels OCI version/revision/source absents, root,
l'absence de HEALTHCHECK, les CVE HIGH/CRITICAL corrigeables et les secrets.
Avec `--push`, une image acceptée est publiée, signée et son SBOM attesté.

| Image | Résultat |
| --- | --- |
| `legacy` | Refus : root, labels manquants, pas de HEALTHCHECK |
| `1.4.2` initiale | Refus : label source absent et CVE connues |
| `1.4.2` reconstruite | Acceptée, publiée, signée et attestée ; aucun problème bloquant |

**Image corrigée :** `shopapi:1.4.2` a été reconstruite avec Node.js 24,
les paquets système mis à jour et les labels requis, sans npm/yarn dans le runtime.
Les tests et les routes vérifiées fonctionnent.
Le scan ne détecte aucune CVE bloquante ni aucun secret.
La porte accepte `1.4.2` et refuse `legacy`.
