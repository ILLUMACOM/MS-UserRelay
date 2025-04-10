FROM node:18-alpine AS builder

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
