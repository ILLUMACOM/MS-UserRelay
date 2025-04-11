# syntax=docker/dockerfile:1.4

##############################################
## 🔨 Build Stage
FROM node:22-alpine AS builder

WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=8192

# Install build tools only if needed (arm64 compatibility)
ARG TARGETPLATFORM
RUN apk --no-cache add curl && \
  if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
    apk --no-cache add python3 build-base && \
    ln -sf /usr/bin/python3 /usr/bin/python; \
  fi

# Enable and configure pnpm
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && corepack prepare pnpm@latest --activate && pnpm fetch

# Copy source code and build
COPY . .

RUN pnpm install --frozen-lockfile --offline --no-optional && \
  pnpm run build && \
  pnpm --filter directus deploy --prod dist && \
  cd dist && \
  node -e 'const fs=require("fs");const f="package.json",{name,version,type,exports,bin}=require(`./${f}`),{packageManager}=require(`../${f}`);fs.writeFileSync(f,JSON.stringify({name,version,type,exports,bin,packageManager},null,2));' && \
  mkdir -p dist/extensions/storage/s3 && cp -r ./extensions/storage/s3 dist/extensions/storage/ && \
  mkdir -p database extensions uploads

##############################################
## 🚀 Runtime Stage
FROM node:22-alpine AS runtime

# Install PM2 only
RUN apk --no-cache add curl && npm install -g pm2@5

# Switch to non-root user for safety
USER node
WORKDIR /app

# Basic runtime ENV
ENV NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    WEBSOCKETS_ENABLED=true

# Copy build artifacts
COPY --from=builder --chown=node:node /app/ecosystem.config.cjs .
COPY --from=builder --chown=node:node /app/dist .

EXPOSE 8055

# Launch Directus via PM2
CMD ["pm2-runtime", "start", "ecosystem.config.cjs"]
