FROM node:20-bookworm-slim AS base
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1

FROM base AS deps
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends nginx-light ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl \
  && cat <<'EOF' > /etc/nginx/ssl/cloudflare-origin.crt
-----BEGIN CERTIFICATE-----

-----END CERTIFICATE-----
EOF

RUN cat <<'EOF' > /etc/nginx/ssl/cloudflare-origin.key
-----BEGIN PRIVATE KEY-----

-----END PRIVATE KEY-----
EOF

RUN chmod 600 /etc/nginx/ssl/cloudflare-origin.key \
  && chmod 644 /etc/nginx/ssl/cloudflare-origin.crt

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.env ./.env

# Nginx config with larger header buffers
COPY docker/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

CMD ["sh", "-c", "nginx && exec node server.js"]
