# Politique de tags

## Tags utilisés

| Tag | Exemple | Règle |
| --- | --- | --- |
| Version complète | `1.4.2`, `1.5.0-rc.1` | Immuable après publication |
| Commit ou build CI | `git-<SHA>`, `build-<date>-<id>` | Immuable pendant sa conservation |
| Branche ou environnement | `main`, `dev`, `staging` | Peut changer, hors production |
| Version abrégée | `1`, `1.4` | Peut changer, hors production |
| Dernière image implicite | `latest` | Interdit en production |


`latest` peut pointer vers une autre image après un push. Un même déploiement
peut donc changer de contenu, ce qui complique la reproduction et le rollback.
Omettre le tag revient aussi à utiliser `latest`.

Pour valider le TP, l'image locale `shopapi:1.4.2` peut être reconstruite avec le
Dockerfile corrigé. Cette opération ne remplace pas le tag déjà publié dans le
registre. La reconstruction est publiée dans `shopapi-rebuilt:1.4.2`, un dépôt
distinct ; l'image initiale et ses preuves de scan restent accessibles dans
`shopapi` par leur digest. Les tags publiés des deux dépôts restent immuables.

## Utiliser un digest dans Compose

Le digest identifie le contenu de l'image. Exemple de l'étape 3 :

```yaml
services:
  shopapi:
    image: registry.local:5000/shopapi@sha256:ab0becf2809387f4c83fc5876773ef6861aa2e743b576c9d2c0e9546ae10b02a
```

Pour changer de version ou revenir en arrière, on modifie ce digest.

## Retaguer sans pull

Depuis `starter/registry`, avec le registre démarré :

```bash
./retag.sh shopapi 1.4.2 tp03-retag-demo
./api.sh digest shopapi 1.4.2
./api.sh digest shopapi tp03-retag-demo
```

Le script utilise `crane tag` en conteneur, avec TLS et authentification.
Il ajoute un tag au même manifeste sans télécharger les couches de l'image.
Les deux commandes de lecture doivent renvoyer le même digest.

Les digests sont identiques, une seconde exécution ne modifie
rien et une destination associée à un autre digest est refusée.

