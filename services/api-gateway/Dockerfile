# Multi-stage minimal production image for DoctorNect Auth Gateway
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

# Copy application code (zero external npm dependencies required)
COPY src/ ./src/
COPY package.json ./

# Security: Non-root execution
RUN addgroup -S doctornect && adduser -S doctornect -G doctornect
USER doctornect

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/healthz || exit 1

CMD ["node", "src/server.js"]
