# Reference app image. Small, non-root, healthcheck-friendly.
FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2

WORKDIR /app

# Install deps first for better layer caching.
COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./
COPY knexfile.js ./
COPY src ./src
COPY migrations ./migrations

ENV PORT=3000
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=10s --start-period=30s --retries=10 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

USER node
CMD ["node", "server.js"]
