# 5. Rapport

## Tableau avant/après

| Critère | Avant : image legacy | Après : image corrigée `shopapi:1.4.2` |
|---|---|---|
| Taille sur disque (`docker image ls`) | 1,06 Go | 212 Mo |
| Taille de contenu affichée par Docker | 279 Mo | 51,7 Mo |
| Nombre de couches du système de fichiers | 9 | 8 |
| Temps de rebuild après changement de code | 5,651 s (`npm install` relancé) | 2,270 s (`npm ci` en cache, tests relancés) |
| Utilisateur | `uid=0(root)` | `uid=1000(node)` |
| Temps d’arrêt | Environ 10 s attendues dans le sujet ; non mesurées sur l’image d’origine | 0,223 s mesurées |



Pour mesurer le rebuild corrigé, depuis la racine du TP, après une première construction :


## Explication du temps d’arrêt


Le tag `shopapi:legacy` a depuis été reconstruit avec le Dockerfile corrigé : son arrêt mesuré de 0,109 s ne représente donc pas le comportement historique. Une comparaison expérimentale avec les 10 secondes attendues nécessite l’image d’origine.

## Dockerfile final

La construction comporte des étapes de dépendances, de tests, de suppression des dépendances de développement et de production. L’image finale utilise Alpine, les dépendances de production et un utilisateur non root.

Après les mesures ci-dessus, `USER node` a été remplacé par `USER 1000:1000`, les identifiants du même utilisateur, pour satisfaire Hadolint. Cette dernière modification a été analysée par Hadolint ; l’image n’a pas été reconstruite depuis.



## Validation Hadolint

**Commande :**

```bash
hadolint starter/shopapi/Dockerfile
```

**Sortie avec USER node :**
```bash
starter/shopapi/Dockerfile:30 DL3066 info: Non-numeric user-id may not be resolvable by host system
```
