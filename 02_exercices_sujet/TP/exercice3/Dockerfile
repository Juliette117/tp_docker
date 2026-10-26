FROM nginx

RUN printf '%s\n' \
    '<!doctype html>' \
    '<html lang="fr">' \
    '<head><meta charset="utf-8"><title>Exercice 03</title></head>' \
    '<body><h1>Exercice 03</h1><p>Hello World</p></body>' \
    '</html>' \
    > /usr/share/nginx/html/index.html

EXPOSE 81
