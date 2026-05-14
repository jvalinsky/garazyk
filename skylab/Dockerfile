# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

FROM denoland/deno:2.1.4

WORKDIR /app

# Copy deno.json first for dependency caching
COPY deno.json .
COPY services/ ./services/

# Copy application source
COPY dev.ts main.ts ./
COPY routes/ ./routes/
COPY static/ ./static/

# Cache dependencies
RUN deno cache dev.ts

EXPOSE 2591

ENV SKYLAB_PORT=2591
ENV SKYLAB_HOST=0.0.0.0

CMD ["run", "-A", "main.ts"]
