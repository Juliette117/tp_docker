
docker build -t exercice-06 .

docker run -d --name exercice-06 \
  -p 8082:80 \
  -v "$(pwd)/site:/usr/share/nginx/html:ro" \exercice-06

  