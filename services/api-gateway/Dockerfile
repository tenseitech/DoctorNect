# Production image for the DoctorNect Auth Gateway
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0
# ALB appends the client address to X-Forwarded-For (see src/client_ip.js).
ENV TRUSTED_PROXY_HOPS=1

# Install runtime dependencies from the lockfile (firebase-admin is required for the
# production token-revocation check; without it every authenticated request is rejected).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

COPY src/ ./src/

# Security: Non-root execution
RUN addgroup -S doctornect && adduser -S doctornect -G doctornect
USER doctornect

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/healthz || exit 1

CMD ["node", "src/server.js"]
