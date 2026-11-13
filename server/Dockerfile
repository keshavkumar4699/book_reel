# Cloro API (Production plan A6): Node 22, Fastify, Postgres.
# Cloud Run sets PORT; DATABASE_URL and keys come from Secret Manager.
# Build from the repository root (the privacy policy and terms live with the
# app):  docker build -f server/Dockerfile .

FROM node:22-slim AS build
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci
COPY server/tsconfig.json server/tsconfig.build.json ./
COPY server/src ./src
RUN npm run build:prod

FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY app/assets/legal ./legal
ENV LEGAL_DIR=/app/legal
USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "dist/src/index.js"]
