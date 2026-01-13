# API Server Container
FROM node:18-slim

# Install Docker CLI (for running sandbox containers)
RUN apt-get update && apt-get install -y \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --only=production

# Copy application
COPY server.js ./

# Non-root user
RUN useradd -m -s /bin/bash runner
USER runner

EXPOSE 3001

CMD ["node", "server.js"]
