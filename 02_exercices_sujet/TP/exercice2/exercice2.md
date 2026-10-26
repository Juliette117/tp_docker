docker build -f Dockerfile -t jeu-2048 .
docker run -d --name jeu-2048 -p 8080:80 jeu-2048
