# Rapport TP02

## Étape 1 — Démonstration de fuite

```sh
cd starter/shop-worker
docker build --file Dockerfile.leak \
  --build-arg DEMO_TOKEN=FAKE_SECRET_TP02_ONLY \
  --tag worker:leak .
docker history --no-trunc worker:leak | grep -F FAKE_SECRET_TP02_ONLY
docker run --rm worker:leak cat /demo-token.txt
```

L'historique contient l'identifiant fictif dans les métadonnées de l'instruction `RUN`, et le conteneur affiche `FAKE_SECRET_TP02_ONLY`.

Passage d'un secret par `ARG`, puis écriture dans le système de fichiers. Un `ARG` n'est pas automatiquement conservé dans `docker inspect ... .Config.Env` et ne crée pas un fichier contenant sa valeur.

## Étape 2 — Secret BuildKit et image multi-stage

Le stage `builder` installe les dépendances, `test` lance les tests et `runtime` contient le worker et ses dépendances de production.

Le fichier `pip.conf` indique à pip quel registre utiliser. Pour le TP, il pointe vers `https://pypi.org/simple`.

BuildKit rend ce fichier disponible uniquement pendant l’installation, grâce au montage secret. Il n’est pas conservé dans l’image.

```sh
docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
docker history --no-trunc worker:1.0
docker run --rm worker:1.0 cat /etc/pip.conf
```

Résultat : les deux tests passent. Le contenu du secret n’apparaît pas dans l’historique et la dernière commande renvoie « No such file or directory », car pip.conf est absent de l’image finale. pytest et ruff sont également absents de cette image. Il faut éviter de copier le secret ou de l’afficher dans les logs pendant le build.

Alternatives :

- Pour télécharger une dépendance Git privée, utiliser `--mount=type=ssh` avec `docker build --ssh default ...`.
- Pour transmettre un jeton depuis une variable locale, utiliser `docker build --secret id=TOKEN,env=TOKEN ...`. Le Dockerfile le lit avec `RUN --mount=type=secret,id=TOKEN ...`, dans `/run/secrets/TOKEN`. La variable TOKEN doit être exportée avant le build.

## Étape 3 — Cache pip

Le montage `--mount=type=cache,target=/root/.cache/pip` garde les paquets téléchargés par pip pour les prochains builds. L’option `--no-cache-dir` a été retirée pour permettre ce stockage. Le cache n’est pas ajouté à l’image finale.

```sh
# Premier build.
time docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
# Même build : Docker réutilise les couches.
time docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
# Réexécuter les instructions.
time docker build --no-cache --secret id=pipconf,src=pip.conf -t worker:1.0 .
```

Mesures réalisées sur une machine arm64 :

| Build | Durée | Résultat |
| --- | --- | --- |
| Premier build | 6,11 s | Installation et tests |
| Build identique | 0,93 s | Couches réutilisées |
| Avec --no-cache | 5,86 s | Instructions réexécutées |
| Avec requests ajouté | 4,47 s | Anciens paquets réutilisés, nouveaux téléchargés |

L’ajout de `requests==2.32.3` a été testé dans une copie temporaire du contexte, sans modifier requirements.txt dans le projet.

**Différence entre les deux caches :**

- Le cache de couches évite de relancer une installation si rien n’a changé.
- Le cache pip évite de retélécharger les paquets disponibles lorsque l’installation doit être relancée.

**Avec `--no-cache`**, Docker réexécute les instructions. Cela ne constitue pas une commande de suppression du cache pip, mais sa réutilisation n’est pas garantie dans tous les cas : nos essais ont montré des téléchargements. Le test avec requests a bien montré `Using cached` pour les anciens paquets.

Contrairement au commentaire du sujet, `docker builder prune` peut aussi supprimer les caches montés.

## Étape 4 — Multi-architecture

On construit le worker pour `amd64` et `arm64` avec un seul build :

```sh
docker buildx create --name shop --driver docker-container
docker buildx inspect shop --bootstrap

docker buildx build --builder shop \
  --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf \
  -t shop-worker:1.0 --output type=oci,dest=worker.tar .
```

`worker.tar` contient les images des deux architectures. Pour les publier dans un registre, remplacer l’export `--output` par `--push` et adapter le tag à l’adresse du registre. Vérifier ensuite avec `docker buildx imagetools inspect ADRESSE_IMAGE`.

Les images ont été construites et inspectées. Les deux tests du worker passent sur chaque plateforme.

| Plateforme | Durée | Sur notre machine arm64 |
| --- | --- | --- |
| amd64 | 7,57 s | Émulée |
| arm64 | 5,57 s | Native |

Ces builds utilisent `--no-cache` et un export OCI. Les temps sont indicatifs : le réseau et les autres opérations Docker influencent aussi les résultats.

**Réponses :**

- **Export :** le builder docker-container ne charge pas automatiquement les images dans Docker. `--push` les publie ; l’export OCI crée une archive locale.
- **Manifest list :** elle référence les images et leurs plateformes. Docker choisit celle adaptée à la machine.
- **Cache par architecture :** `ARG TARGETARCH` et `id=shop-worker-pip-${TARGETARCH}` séparent les caches pip amd64 et arm64.
- **QEMU :** il émule une autre architecture, ce qui peut ralentir le build. L’alternative est un builder avec deux nœuds natifs, ajoutés avec `--append` et `--platform`.

## Étape 5 — Cache distant

Le cache distant permet à plusieurs machines de réutiliser les résultats d’un build. Il est stocké dans un registre accessible depuis le builder.

```sh
REGISTRY=registry.example.com
docker buildx build --builder shop \
  --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf \
  --cache-from "type=registry,ref=$REGISTRY/cache:worker" \
  --cache-to "type=registry,ref=$REGISTRY/cache:worker,mode=max" \
  -t "$REGISTRY/shop-worker:1.0" --output type=oci,dest=worker.tar .
```

- `--cache-from` récupère le cache existant.
- `--cache-to` enregistre le cache pour les prochains builds.
- `mode=min` exporte les couches de l’image finale.
- `mode=max` exporte aussi les étapes intermédiaires exécutées, comme l’installation et les tests. Il prend plus de place mais permet davantage de réutilisation.

Le cache distant ne contient pas le cache pip monté : il permet de réutiliser une installation complète, mais un nouveau builder devra télécharger les paquets si cette installation doit être refaite.

**Variantes :** `type=gha` utilise le cache de GitHub Actions ; `type=s3` utilise un bucket S3 et nécessite une version de BuildKit compatible et des droits AWS. Ces variantes n’ont pas été exécutées.

Un premier builder a exporté le cache dans le registre local. Un deuxième builder, sans cache local, l’a importé : les installations et les tests des deux architectures étaient marqués `CACHED`.

## Étape 6 — docker buildx bake

Le fichier `docker-bake.hcl`, à la racine du TP02, regroupe les builds. Exécuter les commandes suivantes depuis cette racine.

- Groupe `default` : API du TP01 et worker.
- Cible `_common` : labels OCI version/révision, plateformes amd64/arm64 et sources de cache partagées. Le préfixe `_` est une convention, pas un type abstrait imposé par Bake.
- Cible `api` : contexte `../TP01/starter/shopapi`, stage `production`. Les arguments `APP_VERSION` et `GIT_SHA` sont transmis au Dockerfile existant.
- Cible `worker` : stage `runtime`, secret pipconf et cache dédié.
- Cible `worker-test` : stage `test` uniquement et ses prérequis, sans runtime ni image exportée. Les résultats restent dans le cache du builder. Une étape de test déjà en cache n’est pas réexécutée.

### Examiner le plan sans construire

```sh
docker buildx bake --print
docker buildx bake --print worker-test
VERSION=2.0 GIT_SHA=abc123 REGISTRY=registry.example.com REMOTE_CACHE=true docker buildx bake --print
```

Variables : `VERSION=1.0`, `GIT_SHA=local`, `REGISTRY=localhost:5000`, `API_CONTEXT=../TP01/starter/shopapi`, `REMOTE_CACHE=false` par défaut. `REGISTRY` détermine les tags ; il ne déclenche pas de publication à lui seul. `REMOTE_CACHE=true` active les imports et exports de caches registry en mode max. Les exports ont trois références distinctes : `cache:api`, `cache:worker`, `cache:worker-test`. Les builds peuvent importer ces trois sources pour réutiliser les étapes communes.

### Exécuter les tests du worker

Le fichier `starter/shop-worker/pip.conf` doit exister (le recréer à partir de `pip.conf.example` si nécessaire).

```sh
VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake --builder shop worker-test
# Pour forcer la réexécution des instructions du stage test :
docker buildx bake --builder shop --set worker-test.no-cache-filter=test worker-test
```

Si le dossier n’appartient pas à un dépôt Git, remplacer la substitution par `GIT_SHA=local`. Le défaut est multi-architecture : les tests sont construits pour amd64 et arm64.

### Construire et charger toute la stack localement

Sélectionner une seule plateforme pour le chargement local et citer le joker pour éviter son expansion par le shell :

```sh
case "$(uname -m)" in
  x86_64) SHOP_ARCH=amd64 ;;
  arm64|aarch64) SHOP_ARCH=arm64 ;;
  *) echo "Architecture à sélectionner manuellement"; exit 1 ;;
esac
VERSION=1.0 docker buildx bake --builder shop \
  --allow fs.read=../TP01/starter/shopapi \
  --set "*.platform=linux/$SHOP_ARCH" --load
```

L’API se trouve en dehors du répertoire TP02. L’autorisation Bake `fs.read` est limitée à ce contexte et permet son accès lors du build. Si le contexte change via `API_CONTEXT`, adapter également cette option. Elle ne remplace pas les permissions du système de fichiers.

### Exporter la stack multi-architecture sans registre

```sh
docker buildx bake --builder shop \
  --allow fs.read=../TP01/starter/shopapi \
  --allow fs.write=/private/tmp \
  --set 'api.output=type=oci,dest=/tmp/tp02-api.tar' \
  --set 'worker.output=type=oci,dest=/tmp/tp02-worker.tar'
```

Les deux cibles ont des destinations distinctes. Sur macOS, /tmp correspond à /private/tmp : Bake exige aussi l’autorisation d’écriture explicite ci-dessus. Sur Linux, utiliser fs.write=/tmp. Les archives peuvent être remplacées lors d’un nouveau build.

### Publier avec cache distant

Après configuration d’un registre accessible et authentification :

```sh
VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) \
REGISTRY=registry.example.com REMOTE_CACHE=true \
docker buildx bake --builder shop \
  --allow fs.read=../TP01/starter/shopapi --push
```

Remplacer l’adresse fictive par le registre réel. Cette commande publie les images et les caches. Pour le registre local HTTP, utiliser la configuration et le réseau décrits en fin de rapport.

Validation réussie : les plans --print, le groupe default API + worker en multi-architecture (13,98 s, tests réussis) et la cible worker-test (résultats en cache) ont été vérifiés.

Référence : [Bake, héritage, variables et cibles](https://docs.docker.com/build/bake/reference/).

## Reproduire la validation du cache registry local

Les ressources de validation ont été nettoyées après les essais. Exécuter les commandes de création ci-dessous pour les recréer. Elles ne suppriment aucun cache existant.

Depuis la racine du TP02 :

```sh
docker network create tp02-validation
docker run -d --name tp02-registry --network tp02-validation \
  -p 127.0.0.1:5002:5000 registry:2
docker buildx create --name tp02-cache-writer --driver docker-container \
  --driver-opt network=tp02-validation --buildkitd-config validation/buildkitd.toml
docker buildx create --name tp02-cache-reader --driver docker-container \
  --driver-opt network=tp02-validation --buildkitd-config validation/buildkitd.toml
```

Depuis `starter/shop-worker`, remplir le registre avec le premier builder :

```sh
docker buildx build --builder tp02-cache-writer \
  --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf \
  --cache-to type=registry,ref=tp02-registry:5000/cache:worker,mode=max \
  -t tp02-registry:5000/shop-worker:1.0 --push --progress=plain .
```

Puis importer depuis le deuxième builder, sans cache local préalable :

```sh
docker buildx build --builder tp02-cache-reader \
  --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf \
  --cache-from type=registry,ref=tp02-registry:5000/cache:worker \
  --output type=cacheonly --progress=plain .
docker buildx imagetools inspect localhost:5002/shop-worker:1.0
```

Le nom tp02-registry:5000 est résolu sur le réseau Docker partagé par le registre et ces builders ; localhost:5002 est son adresse depuis le poste. Le registre utilise HTTP uniquement pour cette validation locale. Le mode max et la réutilisation des étapes intermédiaires ont été validés pendant les essais.
