# =============================================================================
# STAGE 1: Dependencies - Install and cache workspace dependencies
# =============================================================================
FROM oven/bun:1.2.8 AS deps

WORKDIR /app

# Copy workspace configuration
COPY package.json bun.lock ./

# Copy package.json files for all packages (exclude local db; use published @trycompai/db)
COPY packages/kv/package.json ./packages/kv/
COPY packages/ui/package.json ./packages/ui/
COPY packages/email/package.json ./packages/email/
COPY packages/integration-platform/package.json ./packages/integration-platform/
COPY packages/integrations/package.json ./packages/integrations/
COPY packages/utils/package.json ./packages/utils/
COPY packages/tsconfig/package.json ./packages/tsconfig/
COPY packages/analytics/package.json ./packages/analytics/
COPY packages/auth/package.json ./packages/auth/
COPY packages/billing/package.json ./packages/billing/
COPY packages/company/package.json ./packages/company/
COPY packages/db/package.json ./packages/db/
COPY packages/device-agent/package.json ./packages/device-agent/
COPY packages/docs/package.json ./packages/docs/
COPY packages/framework-editor-cli/package.json ./packages/framework-editor-cli/

# Copy app package.json files
COPY apps/app/package.json ./apps/app/
COPY apps/portal/package.json ./apps/portal/
COPY apps/api/package.json ./apps/api/
COPY apps/framework-editor/package.json ./apps/framework-editor/
COPY apps/browser-extension/security-questionnaire-ext/package.json ./apps/browser-extension/security-questionnaire-ext/

# Install all dependencies
RUN PRISMA_SKIP_POSTINSTALL_GENERATE=true bun install --ignore-scripts

# =============================================================================
# STAGE 2: Ultra-Minimal Migrator - Only Prisma
# =============================================================================
FROM oven/bun:1.2.8 AS migrator

WORKDIR /app

# Copy local Prisma schema and migrations from workspace
COPY packages/db/prisma ./packages/db/prisma

# Create minimal package.json for Prisma runtime (also used by seeder)
RUN echo '{"name":"migrator","type":"module","dependencies":{"prisma":"^6.14.0","@prisma/client":"^6.14.0","@trycompai/db":"^1.3.4","zod":"^3.25.7"}}' > package.json

# Install ONLY Prisma dependencies
RUN bun install

# Ensure Prisma can find migrations relative to the published schema path
# We copy the local migrations into the published package's dist directory
RUN cp -R packages/db/prisma/migrations node_modules/@trycompai/db/dist/

# Run migrations against the combined schema published by @trycompai/db
RUN echo "Running migrations against @trycompai/db combined schema"
CMD ["bunx", "prisma", "migrate", "deploy", "--schema=node_modules/@trycompai/db/dist/schema.prisma"]

# =============================================================================
# STAGE 3: App Builder
# =============================================================================
FROM deps AS app-builder

WORKDIR /app

# Copy all source code needed for build
COPY packages ./packages
COPY apps/app ./apps/app

# Bring in node_modules for build and prisma prebuild
COPY --from=deps /app/node_modules ./node_modules

# Pre-combine schemas and generate the Prisma client into
# node_modules/@prisma/client. The deps stage ran `bun install` with
# `--ignore-scripts` so packages/db's postinstall was skipped; we run
# it explicitly here so `next build` can resolve the generated runtime
# + types when it imports @prisma/client.
RUN cd packages/db && node scripts/combine-schemas.js \
                   && node scripts/generate-prisma-client-js.js

# Workspace consumers import @trycompai/db through its dist entrypoint.
RUN mkdir -p packages/db/dist \
    && printf "%s\n" "export * from '@prisma/client';" > packages/db/dist/index.js

# Ensure Next build has required public env at build-time
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ARG NEXT_PUBLIC_PORTAL_URL
ARG NEXT_PUBLIC_POSTHOG_KEY
ARG NEXT_PUBLIC_POSTHOG_HOST
ARG NEXT_PUBLIC_IS_DUB_ENABLED
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL \
    NEXT_PUBLIC_PORTAL_URL=$NEXT_PUBLIC_PORTAL_URL \
    NEXT_PUBLIC_POSTHOG_KEY=$NEXT_PUBLIC_POSTHOG_KEY \
    NEXT_PUBLIC_POSTHOG_HOST=$NEXT_PUBLIC_POSTHOG_HOST \
    NEXT_PUBLIC_IS_DUB_ENABLED=$NEXT_PUBLIC_IS_DUB_ENABLED \
    NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_TELEMETRY_DISABLED=1 NODE_ENV=production \
    NEXT_OUTPUT_STANDALONE=true \
    NODE_OPTIONS=--max_old_space_size=6144

# These workspace packages publish only their built dist entrypoints.
RUN cd packages/auth && bun run build \
    && cd ../company && bun run build \
    && cd ../billing && bun run build

# Run Next with Node. Bun 1.2.8 can crash after a Next 16 Turbopack build.
RUN cd apps/app \
    && bunx prisma generate --schema=prisma/schema \
    && node ../../packages/db/scripts/fix-generated-extensions.js src/generated/prisma \
    && SKIP_ENV_VALIDATION=true node ../../node_modules/next/dist/bin/next build

# =============================================================================
# STAGE 4: App Production
# =============================================================================
FROM node:22-alpine AS app

WORKDIR /app

# Copy Next standalone output
COPY --from=app-builder /app/apps/app/.next/standalone ./
COPY --from=app-builder /app/apps/app/.next/static ./apps/app/.next/static
COPY --from=app-builder /app/apps/app/public ./apps/app/public

EXPOSE 3000
CMD ["node", "apps/app/server.js"]

# =============================================================================
# STAGE 5: Portal Builder
# =============================================================================
FROM deps AS portal-builder

WORKDIR /app

# Copy all source code needed for build
COPY packages ./packages
COPY apps/portal ./apps/portal

# Bring in node_modules for build and prisma prebuild
COPY --from=deps /app/node_modules ./node_modules

# Pre-combine schemas and generate the Prisma client for portal build.
RUN cd packages/db && node scripts/combine-schemas.js \
                   && node scripts/generate-prisma-client-js.js
RUN mkdir -p packages/db/dist \
    && printf "%s\n" "export * from '@prisma/client';" > packages/db/dist/index.js
RUN cp packages/db/dist/schema.prisma apps/portal/prisma/schema/schema.prisma \
    && sed -i 's#output          = "../src/generated/prisma"#output          = "../../src/generated/prisma"#' \
      apps/portal/prisma/schema/schema.prisma

# Ensure Next build has required public env at build-time
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL \
    NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_TELEMETRY_DISABLED=1 NODE_ENV=production \
    NEXT_OUTPUT_STANDALONE=true \
    NODE_OPTIONS=--max_old_space_size=6144

# These workspace packages publish only their built dist entrypoints.
RUN cd packages/auth && bun run build \
    && cd ../company && bun run build

# Run Next with Node. Bun 1.2.8 can crash after a Next 16 Turbopack build.
RUN cd apps/portal \
    && bunx prisma generate --schema=prisma/schema \
    && node ../../packages/db/scripts/fix-generated-extensions.js src/generated/prisma \
    && SKIP_ENV_VALIDATION=true node ../../node_modules/next/dist/bin/next build

# =============================================================================
# STAGE 6: Portal Production
# =============================================================================
FROM node:22-alpine AS portal

WORKDIR /app

# Copy Next standalone output for portal
COPY --from=portal-builder /app/apps/portal/.next/standalone ./
COPY --from=portal-builder /app/apps/portal/.next/static ./apps/portal/.next/static
COPY --from=portal-builder /app/apps/portal/public ./apps/portal/public

EXPOSE 3000
CMD ["node", "apps/portal/server.js"]

# (Trigger.dev hosted; no local runner stage)
