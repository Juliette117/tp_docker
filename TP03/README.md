# TP03

[Sujet](TP03.md) · [Rapport](RAPPORT.md) · [Politique de tags](TAGGING.md)


## Registre

```bash
./starter/registry/setup.sh
docker compose -f starter/registry/compose.yml up -d --wait
```

UI : https://registry.local:5000 — mirror : http://localhost:5001.
Comptes : `ci` / `ci-push-2024` (push), `dev` / `dev-pull-2024` (pull).

Première configuration du client sur macOS :

```bash
sudo python3 starter/registry/configure-client.py hosts
docker desktop stop --timeout 120
python3 starter/registry/configure-client.py desktop
docker desktop start --timeout 120
```

Les images `shopapi:1.4.2` et `shopapi:legacy` doivent être disponibles localement.
Publier l'image initiale :

```bash
docker login registry.local:5000 -u ci
docker tag shopapi:1.4.2 registry.local:5000/shopapi:1.4.2
docker push registry.local:5000/shopapi:1.4.2
```

## Commandes du TP

```bash
./starter/registry/api.sh catalog
./starter/registry/api.sh tags shopapi
./starter/registry/api.sh digest shopapi 1.4.2
./starter/registry/retention.sh DEPOT 2  # aperçu ; ajouter --apply pour supprimer
./starter/registry/garbage-collect.sh   # simulation ; --apply pour appliquer
./starter/registry/retag.sh shopapi 1.4.2 tp03-retag-demo
./starter/supply-chain/step4.sh
```

## Release

Reconstruire `shopapi:1.4.2` depuis les sources du TP01 avec le Dockerfile corrigé :
Node.js 24, mise à niveau des paquets système, labels OCI requis et runtime sans
npm/yarn. Les tests du TP01 sont exécutés pendant le build.

```bash
docker build --build-arg GIT_SHA="$(git rev-parse HEAD)" \
  -f starter/Dockerfile.release-candidate -t shopapi:1.4.2 ../TP01/starter/shopapi
./starter/release-gate.sh shopapi:legacy  # doit refuser
./starter/release-gate.sh shopapi:1.4.2  # doit accepter après correction
```

L'image locale `1.4.2` est remplacée par la reconstruction. Les scans de l'étape 4
concernent l'image initiale, conservée dans le registre par son digest.

Pour publier, signer et attester la reconstruction sans remplacer le tag déjà
publié dans `shopapi`, utiliser un dépôt distinct pour cette variante du TP :

```bash
./starter/release-gate.sh shopapi:1.4.2 --push registry.local:5000/shopapi-rebuilt:1.4.2
```

La porte retourne 0 si tous les contrôles demandés réussissent. Les résultats
sont dans `artifacts/`. Un tag publié ne peut pas être remplacé par un autre digest.
