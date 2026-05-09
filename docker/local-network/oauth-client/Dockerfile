FROM node:20-slim AS builder
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
RUN npm run build

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /app/dist /app
COPY client-metadata.json /app/client-metadata.json
EXPOSE 8080
CMD ["python3", "-m", "http.server", "8080"]
