# DoctorNect Auth Gateway — build from repository root:
#   docker build -f services/api-gateway/Dockerfile .
#
FROM node:22-alpine AS deps

WORKDIR /app/gateway

COPY services/api-gateway/package.json services/api-gateway/package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runner

WORKDIR /app/gateway

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

COPY --from=deps /app/gateway/node_modules ./node_modules
COPY services/api-gateway/package.json ./
COPY services/api-gateway/src ./src

# Shared monorepo modules (server.js requires ../../../scripts/lib/*)
COPY scripts/lib/bootstrap_root_env.js \
  scripts/lib/repo_root.js \
  scripts/lib/parse_env_file.js \
  scripts/lib/env_duplicate_keys.js \
  scripts/lib/demo_routing.js \
  scripts/lib/trusted_client_ip.js \
  /app/scripts/lib/

# Repo root marker for findRepoRoot() when .env is injected at runtime (ECS), not baked in
COPY .env.example /app/.env.example

RUN addgroup -S doctornect && adduser -S doctornect -G doctornect \
  && chown -R doctornect:doctornect /app/gateway /app/scripts

USER doctornect

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/healthz || exit 1

CMD ["node", "src/server.js"]