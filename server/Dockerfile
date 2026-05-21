FROM node:20-alpine AS base
WORKDIR /app
RUN apk add --no-cache wget

# Dependencies
FROM base AS deps
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Production image
FROM base AS production
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 3000
CMD ["node", "src/index.js"]
