# Bsky dataplane — schema init + gRPC server
# Builds from bluesky-social/atproto using the existing services/bsky/Dockerfile
# structure, but overrides the entry point to run dataplane.js instead of api.js.
#
# The dataplane:
#   1. Creates the bsky schema (CREATE SCHEMA IF NOT EXISTS)
#   2. Runs all Kysely migrations to latest
#   3. Starts the gRPC DataPlane server on port 2585
#
# This is the same pattern used by Blacksky (outof-coffee/atproto) for running
# rsky-wintermute alongside the reference dataplane.

FROM node:20.20-alpine AS build

RUN corepack enable

WORKDIR /app

COPY ./package.json ./
RUN corepack prepare --activate

# Move files into the image and install
COPY ./*.* ./
COPY ./tsconfig ./tsconfig
COPY ./lexicons ./lexicons
COPY ./packages/internal ./packages/internal
COPY ./packages/lex ./packages/lex

# bsky's transitive dependencies
COPY ./packages/api ./packages/api
COPY ./packages/aws ./packages/aws
COPY ./packages/bsky ./packages/bsky
COPY ./packages/common-web ./packages/common-web
COPY ./packages/common ./packages/common
COPY ./packages/crypto ./packages/crypto
COPY ./packages/did ./packages/did
COPY ./packages/identity ./packages/identity
COPY ./packages/lex-cli ./packages/lex-cli
COPY ./packages/lexicon ./packages/lexicon
COPY ./packages/oauth ./packages/oauth
COPY ./packages/pds ./packages/pds
COPY ./packages/repo ./packages/repo
COPY ./packages/sync ./packages/sync
COPY ./packages/syntax ./packages/syntax
COPY ./packages/ws-client ./packages/ws-client
COPY ./packages/xrpc-server ./packages/xrpc-server
COPY ./packages/xrpc ./packages/xrpc

COPY ./services/bsky ./services/bsky

# install all deps
RUN PUPPETEER_SKIP_DOWNLOAD=true pnpm install --frozen-lockfile
# build all packages with external node_modules
RUN pnpm run --recursive --stream --filter '@atproto/crypto...' build
RUN pnpm run --recursive --stream --filter '@atproto/bsky...' build
# install only prod deps, hoisted to root node_modules dir
RUN pnpm install --prod --shamefully-hoist --frozen-lockfile --prefer-offline --config.confirmModulesPurge=false

WORKDIR services/bsky

# Runtime stage
FROM node:20.20-alpine

RUN apk add --update dumb-init wget

# Avoid zombie processes, handle signal forwarding
ENTRYPOINT ["dumb-init", "--"]

WORKDIR /app/services/bsky
COPY --from=build /app /app

# Copy our custom dataplane.js entry point (from overlayDir)
COPY --from=build /app/services/bsky/dataplane.js ./

EXPOSE 2585
ENV BSKY_DATAPLANE_PORT=2585
ENV NODE_ENV=production

USER node
CMD ["node", "--enable-source-maps", "dataplane.js"]

LABEL org.opencontainers.image.source=https://github.com/bluesky-social/atproto
LABEL org.opencontainers.image.description="Bsky DataPlane (schema init + gRPC)"
LABEL org.opencontainers.image.licenses=MIT
