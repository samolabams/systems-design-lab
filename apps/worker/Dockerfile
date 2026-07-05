FROM cgr.dev/chainguard/node:latest-dev@sha256:cb5ca16a7d09b83cbcb0fcedd2e26ef30bc22b011e2ab372684c7d612c64c66b AS deps
USER root
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

FROM cgr.dev/chainguard/node:latest@sha256:5280e63c3d2c81366056926b79f27f70e4adbd3a03a5b45c53503eac2b722b3f
WORKDIR /app
COPY --from=deps --chown=65532:65532 /app/node_modules ./node_modules
COPY --chown=65532:65532 server.js ./
COPY --chown=65532:65532 src ./src
CMD ["server.js"]
