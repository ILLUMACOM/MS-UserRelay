# syntax=docker/dockerfile:1.4

##############################################
## 🔨 Build Stage
FROM node:18-alpine AS builder

WORKDIR /directus
ARG TARGETPLATFORM
ENV NODE_OPTIONS=--max-old-space-size=8192

# Install curl + build tools for arm64 if needed
RUN <<EOF
  apk --no-cache add curl
  if [ "$TARGETPLATFORM" = 'linux/arm64' ]; then
    apk --no-cache add python3 build-base
    ln -sf /usr/bin/python3 /usr/bin/python
  fi
EOF

COPY package.json .
RUN corepack enable && corepack prepare

COPY pnpm-lock.yaml .
RUN pnpm fetch

COPY . .

RUN <<EOF
  pnpm install --recursive --offline --frozen-lockfile
  npm_config_workspace_concurrency=1 pnpm run build
  pnpm --filter directus deploy --prod dist
  cd dist
  node -e '
    const fs = require("fs");
    const f = "package.json", {name, version, type, exports, bin} = require(`./${f}`), {packageManager} = require(`../${f}`);
    fs.writeFileSync(f, JSON.stringify({name, version, type, exports, bin, packageManager}, null, 2));
  '
  mkdir -p database extensions uploads
EOF

##############################################
## 🚀 Runtime Stage
FROM node:18-alpine AS runtime

RUN apk --no-cache add curl && npm install --global pm2@5

USER node
WORKDIR /directus

EXPOSE 8055

ENV \
  NODE_ENV="production" \
  NPM_CONFIG_UPDATE_NOTIFIER="false" \
  WEBSOCKETS_ENABLED="true"

COPY --from=builder --chown=node:node /directus/ecosystem.config.cjs .
COPY --from=builder --chown=node:node /directus/dist .

CMD : \
  && node cli.js bootstrap \
  && pm2-runtime start ecosystem.config.cjs ;
