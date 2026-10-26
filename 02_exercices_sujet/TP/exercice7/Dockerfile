# Image officielle du serveur MySQL
FROM mysql:8.4

# MySQL exécute automatiquement ce script lors de la première initialisation.
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

EXPOSE 3306
