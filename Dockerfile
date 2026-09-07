FROM node:24-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

FROM base AS build
WORKDIR /app
COPY . /app

RUN corepack enable
RUN apk add --no-cache python3 alpine-sdk

RUN pnpm install --prod --frozen-lockfile

RUN pnpm deploy --filter=@imput/cobalt-api --prod /prod/api

# Railway no incluye .git en el contexto de build, por eso el COPY del .git se
# quito en e419f50e. Pero packages/version-info aborta el arranque entero si no
# encuentra un repositorio ("no git repository root found"), asi que aqui se
# genera uno minimo con los tres archivos que llega a leer:
#   .git/HEAD       -> rama
#   .git/logs/HEAD  -> commit (segundo campo de la ultima linea)
#   .git/config     -> remote
ARG GIT_COMMIT=0000000000000000000000000000000000000000
ARG GIT_BRANCH=main
ARG GIT_REMOTE=https://github.com/leonhuesitos-star/cobalt.git
RUN mkdir -p /prod/api/.git/logs && \
    echo "ref: refs/heads/${GIT_BRANCH}" > /prod/api/.git/HEAD && \
    echo "${GIT_COMMIT} ${GIT_COMMIT} railway <ci@railway.app> 0 +0000	clone: from ${GIT_REMOTE}" > /prod/api/.git/logs/HEAD && \
    printf '[remote "origin"]\n\turl = %s\n' "${GIT_REMOTE}" > /prod/api/.git/config

FROM base AS api
WORKDIR /app

COPY --from=build --chown=node:node /prod/api /app

USER node

EXPOSE 9000

# YouTube exige login desde IPs de centro de datos y responde
# error.api.youtube.login. Cobalt se lo salta con cookies, que lee del archivo
# indicado en COOKIE_PATH. Se escribe en /tmp y no en /app porque /app
# pertenece a root y cobalt corre como usuario node.
# En Railway no hay forma de subir un archivo al
# contenedor, asi que se escribe al arrancar desde COOKIES_B64 (el cookies.json
# de cobalt codificado en base64). Sin esa variable, arranca igual y sin cookies.
CMD ["sh", "-c", "if [ -n \"$COOKIES_B64\" ]; then echo \"$COOKIES_B64\" | base64 -d > /tmp/cookies.json && echo '[cookies] cookies.json escrito desde COOKIES_B64'; else echo '[cookies] COOKIES_B64 no definida, sin cookies'; fi; exec node src/cobalt"]
