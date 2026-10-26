FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Maintient le processus principal en attente indéfiniment.
# Le conteneur reste actif pour utiliser ping avec docker exec.
CMD ["sleep", "infinity"]
