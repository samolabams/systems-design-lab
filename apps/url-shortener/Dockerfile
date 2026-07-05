# Reference app image. Small, non-root, healthcheck-friendly.
FROM cgr.dev/chainguard/node:latest-dev@sha256:cb5ca16a7d09b83cbcb0fcedd2e26ef30bc22b011e2ab372684c7d612c64c66b AS deps
USER root

WORKDIR /app

# Install deps first for better layer caching.
COPY package.json ./
RUN npm install --omit=dev

FROM cgr.dev/chainguard/node:latest@sha256:5280e63c3d2c81366056926b79f27f70e4adbd3a03a5b45c53503eac2b722b3f
WORKDIR /app

COPY --from=deps --chown=65532:65532 /app/node_modules ./node_modules
COPY --chown=65532:65532 server.js ./
COPY --chown=65532:65532 knexfile.js ./
COPY --chown=65532:65532 src ./src
COPY --chown=65532:65532 migrations ./migrations

ENV PORT=3000
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=10s --start-period=30s --retries=10 \
  CMD ["/usr/bin/node", "-e", "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

CMD ["server.js"]
