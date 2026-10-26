open -a Docker

docker build -t ubuntu-nginx .
docker run -d --name exercice-01 -p 8080:80 ubuntu-nginx
