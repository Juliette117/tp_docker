
# 1. Diagnostic

##  Taille / performance

### - Image au-dessus de la limite de 200 Mo

### Preuve :
**Commande :**
```sh
docker image inspect shopapi:legacy --format '{{.Size}}'
```
**Sortie :**
```text
279149717
```
**Impact :** la taille rapportée par Docker est d’environ 279 Mo, au-dessus du seuil du sujet. Les transferts et le stockage sont plus coûteux. 

### - Outils de compilation et de maintenance conservés en production

### Preuve : 
**Commande :**
```sh
sed -n '5p' starter/shopapi/Dockerfile
docker run --rm --entrypoint sh shopapi:legacy -c 'du -sh /usr/lib/gcc'
```
**Sortie :**
```text
RUN apt-get install -y curl wget vim git build-essential python3
90M     /usr/lib/gcc
```
**Impact :** le compilateur et les outils de maintenance alourdissent l’image.

### - Index APT et cache npm conservés

#### Preuve : 
**Commande :**
```sh
docker run --rm --entrypoint sh shopapi:legacy -c 'du -sh /root/.npm /var/lib/apt/lists'
```
**Sortie :**
```text
34M     /root/.npm
77M     /var/lib/apt/lists
```
**Impact :** Des fichiers de cache et d’index restent dans le système de fichiers alors qu’ils ne servent pas à exécuter l’API.

### - Dépendances de développement et nodemon global embarqués

### Preuve : 

**Commande :**
```sh
docker run --rm --entrypoint sh shopapi:legacy -c 'npm ls eslint nodemon --depth=0; npm ls -g nodemon --depth=0'
```
**Sortie :**
```text
shopapi@1.4.2 /app
+-- eslint@9.39.5
`-- nodemon@3.1.14

/usr/lib
`-- nodemon@3.1.14
```
**Impact :** ESLint et deux installations de nodemon sont conservés alors que le script de démarrage lance simplement Node. Ca ajoute des fichiers et des dépendances inutiles à l’exécution.

### - Ordre des couches défavorable au cache

### Preuve : 

**Commande :**
```sh
sed -n '10,11p' starter/shopapi/Dockerfile
```
**Sortie :**
```text
COPY . /app
RUN npm install
```
**Impact :** une modification d’un fichier copié invalide la couche `COPY`, puis la couche `npm install`.

##  Sécurité

### - Processus exécuté en root

### Preuve : 

**Commande :**
```sh
docker run --rm --entrypoint sh shopapi:legacy -c 'id'
```
**Sortie :**
```text
uid=0(root) gid=0(root) groups=0(root)
```
**Impact :** une compromission de l’application donne les privilèges root dans le conteneur.

### - Identifiants de base de données intégrés au Dockerfile

### Preuve :
**Commande :**
```sh
rg -n 'DATABASE_URL' starter/shopapi/Dockerfile
docker run --rm --entrypoint sh shopapi:legacy -c 'printenv DATABASE_URL'
```
**Sortie :**
```text
13:ENV DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop
postgres://shop:S3cret!@db.internal:5432/shop
```
**Impact :** le secret est dans la configuration de l’image et exposé.

### - Fichier .env, dump SQL et fichiers inutiles copiés

### Preuve : 
**Commande :**
```sh
docker run --rm --entrypoint sh shopapi:legacy -c 'ls -la /app'
```
**Sortie, extrait :**
```text
-rw-r--r--   1 root root  6148 Oct 26 09:15 .DS_Store
-rw-r--r--   1 root root   179 Oct 26 09:15 .env
-rw-r--r--   1 root root   505 Oct 26 09:15 Dockerfile
-rw-r--r--   1 root root    47 Oct 26 09:15 dump-prod-2024.sql
-rw-r--r--   1 root root   545 Oct 26 09:15 package.json
drwxr-xr-x   2 root root  4096 Oct 26 09:15 src
drwxr-xr-x   2 root root  4096 Oct 26 09:15 test
```
**Impact :** le `.env` peut diffuser des secrets ; le dump SQL peut exposer des données.


##  Exploitabilité

### - Démarrage shell via npm

### Preuve : 
**Commande :**
```sh
docker image inspect shopapi:legacy --format '{{json .Config.Cmd}}'
```
**Sortie :**
```text
["/bin/sh","-c","npm start"]
```
**Impact :** le processus initial est un shell et le lancement passe ensuite par npm. Cette chaîne peut empêcher le signal d’arrêt d’atteindre correctement Node et son gestionnaire `SIGTERM`. 

### - Absence de HEALTHCHECK

### Preuve : 

**Commande :**
```sh
docker image inspect shopapi:legacy --format '{{json .Config.Healthcheck}}'
```
**Sortie :**
```text
null
```
**Impact :** Docker ne dispose pas d’un check de santé intégré pour distinguer un processus actif d’une API qui répond correctement.


### - Build insuffisamment verrouillé

Preuve : 

**Commandes :**
```sh
test -f starter/shopapi/package-lock.json; echo "lockfile_present=$?"
rg -n 'FROM|npm' starter/shopapi/Dockerfile
hadolint starter/shopapi/Dockerfile
```
**Sorties, extraits :**
```text
lockfile_present=1
2:FROM ubuntu:22.04
8:RUN npm install -g nodemon
11:RUN npm install
starter/shopapi/Dockerfile:5 DL3008 warning: Pin versions in apt get install.
starter/shopapi/Dockerfile:7 DL3008 warning: Pin versions in apt get install.
starter/shopapi/Dockerfile:8 DL3016 warning: Pin versions in npm.
```
**Impact :** aucun lockfile n’est fourni dans le contexte source, les paquets système et nodemon global ne sont pas épinglés, et le tag de base est mutable. Deux builds sans cache peuvent résoudre des versions différentes. Le `package-lock.json` visible dans l’image est créé pendant `npm install` ; il ne verrouille pas les builds suivants depuis les sources.

### - Tests et lint absents du build

**Commande :**
```sh
rg -n 'FROM|RUN' starter/shopapi/Dockerfile
```
**Sortie :**
```text
2:FROM ubuntu:22.04
4:RUN apt-get update
5:RUN apt-get install -y curl wget vim git build-essential python3
6:RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
7:RUN apt-get install -y nodejs
8:RUN npm install -g nodemon
11:RUN npm install
```
**Impact :** aucune étape dédiée aux tests ni aucune commande `npm test` ou `npm run lint` n’est exécutée. Une image peut être produite malgré des tests en échec. Le standard imposant leur exécution pendant le build n’est pas respecté.

### 16. Environnement de développement en production

### Preuve : 

**Commande :**
```sh
docker run --rm --entrypoint sh shopapi:legacy -c 'printf "NODE_ENV="; printenv NODE_ENV'
```
**Sortie :**
```text
NODE_ENV=development
```
**Impact :** les bibliothèques peuvent adopter des comportements de développement. La configuration ne correspond pas à l’usage de production attendu.


# 2. Mesurer l'invalidation du cache

**Commande :**
```bash
time docker build --progress=plain -t shopapi:legacy .
echo "// commentaire" >> src/server.js
time docker build --progress=plain -t shopapi:legacy .
```

**Sortie :**
```bash
[+] Building 0.4s (14/14) FINISHED                                                                    docker:desktop-linux
 => [internal] load build definition from Dockerfile                                                                  0.0s
 => => transferring dockerfile: 544B                                                                                  0.0s
 => [internal] load metadata for docker.io/library/ubuntu:22.04                                                       0.3s
 => [internal] load .dockerignore                                                                                     0.0s
 => => transferring context: 2B                                                                                       0.0s
 => [1/9] FROM docker.io/library/ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d189895  0.0s
 => => resolve docker.io/library/ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d189895  0.0s
 => [internal] load build context                                                                                     0.0s
 => => transferring context: 302B                                                                                     0.0s
 => CACHED [2/9] RUN apt-get update                                                                                   0.0s
 => CACHED [3/9] RUN apt-get install -y curl wget vim git build-essential python3                                     0.0s
 => CACHED [4/9] RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -                                        0.0s
 => CACHED [5/9] RUN apt-get install -y nodejs                                                                        0.0s
 => CACHED [6/9] RUN npm install -g nodemon                                                                           0.0s
 => CACHED [7/9] WORKDIR /app                                                                                         0.0s
 => CACHED [8/9] COPY . /app                                                                                          0.0s
 => CACHED [9/9] RUN npm install                                                                                      0.0s
 => exporting to image                                                                                                0.0s
 => => exporting layers                                                                                               0.0s
 => => exporting manifest sha256:3420585a0540ba0db9977212fef206353a811ee32537166cf79cf8ea6e3b6013                     0.0s
 => => exporting config sha256:d8adc372d69207bd68d97224f098963eb7eddccfcc391ed4409070e97e4003a4                       0.0s
 => => exporting attestation manifest sha256:591698c596931fbea99719636b73d5d6815cf233b165f2c11f3faaa9cf694596         0.0s
 => => exporting manifest list sha256:2cc6435c7b3776bc1e648abf05d7e9c65d390f43eef088d180d815997f9af6df                0.0s
 => => naming to docker.io/library/shopapi:legacy                                                                     0.0s
 => => unpacking to docker.io/library/shopapi:legacy                                                                  0.0s

 1 warning found (use docker --debug to expand):
 - JSONArgsRecommended: JSON arguments recommended for CMD to prevent unintended behavior related to OS signals (line 15)
docker build -t shopapi:legacy .  0.09s user 0.08s system 30% cpu 0.548 total
[+] Building 5.7s (14/14) FINISHED                                                                    docker:desktop-linux
 => [internal] load build definition from Dockerfile                                                                  0.0s
 => => transferring dockerfile: 544B                                                                                  0.0s
 => [internal] load metadata for docker.io/library/ubuntu:22.04                                                       0.2s
 => [internal] load .dockerignore                                                                                     0.0s
 => => transferring context: 2B                                                                                       0.0s
 => [1/9] FROM docker.io/library/ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d189895  0.0s
 => => resolve docker.io/library/ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d189895  0.0s
 => [internal] load build context                                                                                     0.0s
 => => transferring context: 4.52kB                                                                                   0.0s
 => CACHED [2/9] RUN apt-get update                                                                                   0.0s
 => CACHED [3/9] RUN apt-get install -y curl wget vim git build-essential python3                                     0.0s
 => CACHED [4/9] RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -                                        0.0s
 => CACHED [5/9] RUN apt-get install -y nodejs                                                                        0.0s
 => CACHED [6/9] RUN npm install -g nodemon                                                                           0.0s
 => CACHED [7/9] WORKDIR /app                                                                                         0.0s
 => [8/9] COPY . /app                                                                                                 0.3s
 => [9/9] RUN npm install                                                                                             4.0s
 => exporting to image                                                                                                1.1s 
 => => exporting layers                                                                                               0.8s 
 => => exporting manifest sha256:191958518f9e140cea9358b53c79a45b1b6ed3424dbcf6aed14ee92ceb9d0678                     0.0s 
 => => exporting config sha256:cabdbb00685b4acc9258e89d39d6c6fcc92ea6020e8edc6786da9b26891106bc                       0.0s 
 => => exporting attestation manifest sha256:a25c6058fd9d99d68eb2e72568a66c729f7e9fcbf4b651835ee4cb96987d5492         0.0s
 => => exporting manifest list sha256:68c41522f24e284646179d1416d081ca620af49ebd4ae35eda487f904d6ae847                0.0s
 => => naming to docker.io/library/shopapi:legacy                                                                     0.0s
 => => unpacking to docker.io/library/shopapi:legacy                                                                  0.2s

 1 warning found (use docker --debug to expand):
 - JSONArgsRecommended: JSON arguments recommended for CMD to prevent unintended behavior related to OS signals (line 15)
docker build -t shopapi:legacy .  0.12s user 0.09s system 3% cpu 5.905 total
```


#### Pourquoi `npm install` est rejoué

Le Dockerfile historique copie tout le contexte avant d’installer les dépendances :

```dockerfile
COPY . /app
RUN npm install
```

L’ajout du commentaire modifie le contenu de `src/server.js`. Le cache de `COPY . /app` ne correspond donc plus aux fichiers à copier. La couche est reconstruite, ce qui invalide également le cache de l’instruction suivante, `RUN npm install`, même si `package.json` n’a pas changé. Les instructions précédant `COPY` restent en cache.


#### Ordre idéal des couches

```text
Image Node officielle à version épinglée
                  │
                  ▼
           WORKDIR /app
                  │
                  ▼
COPY package.json package-lock.json ./
                  │
                  ▼
              RUN npm ci
    (cache conservé si seuls les sources changent)
                  │
                  ▼
           COPY src ./src
    (reconstruit après modification du code)
                  │
                  ▼
   Configuration de l’image et utilisateur node
                  │
                  ▼
      CMD ["node", "src/server.js"]
```

# 3. Vérifier la conformité

Le Dockerfile corrigé utilise la forme exec `CMD ["node", "src/server.js"]`. Node s’exécute en PID 1 et reçoit directement le signal `SIGTERM` envoyé par `docker stop`. Le gestionnaire présent dans `src/server.js` appelle `server.close()`, ferme les connexions PostgreSQL et Redis lorsqu’elles sont configurées.
Dans l’ancienne configuration, le démarrage par un shell et npm pouvait empêcher la transmission correcte du signal à Node. Si le processus ne termine pas après `SIGTERM`, Docker attend le délai d’arrêt par défaut de 10 secondes sur Linux, puis envoie `SIGKILL` pour imposer l’arrêt. Ca explique le délai d’environ 10 secondes pour l’image d’origine.

