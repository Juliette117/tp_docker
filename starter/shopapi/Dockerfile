FROM node:20-alpine AS dependencies
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

FROM dependencies AS test
COPY src ./src
COPY test ./test
RUN npm test && npm run lint

FROM test AS production-dependencies
RUN npm prune --omit=dev

FROM node:20-alpine AS production
WORKDIR /app

ARG APP_VERSION=1.4.2
ARG GIT_SHA=local
LABEL org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION}

COPY --from=production-dependencies --chown=node:node /app/node_modules ./node_modules
COPY --from=test --chown=node:node /app/src ./src
COPY --chown=node:node package.json ./

USER 1000:1000
EXPOSE 3000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD ["node", "-e", "const http = require('node:http'); const req = http.get('http://127.0.0.1:3000/health', res => { res.resume(); process.exit(res.statusCode === 200 ? 0 : 1); }); req.setTimeout(2000, () => req.destroy()); req.on('error', () => process.exit(1));"]
CMD ["node", "src/server.js"]
