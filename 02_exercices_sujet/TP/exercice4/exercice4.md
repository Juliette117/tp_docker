docker build -f Dockerfile -t ubuntu-ping .
docker network create reseau-exercice-04

docker run -d --name conteneur-1 --network reseau-exercice-04 ubuntu-ping
docker run -d --name conteneur-2 --network reseau-exercice-04 ubuntu-ping

docker exec conteneur-1 ping -c 4 conteneur-2
docker exec conteneur-2 ping -c 4 conteneur-1

----

#### Résultat
--- conteneur-1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3067ms