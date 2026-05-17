# Docker Client (`@garazyk/docker-client`)

This package provides an abstracted interface for programmatically invoking Docker CLI and Docker Compose commands via Deno. It is heavily utilized by the Scenario Runner to manage the ATProto environment lifecycle.

## API Highlights

- **`startLocalNetwork()`**: Reads the rendered topology manifest and spins up the environment via `docker compose`.
- **`stopLocalNetwork()`**: Tear down the environment and execute cleanup/diagnostics collection.
- **`ContainerEventWatcher`**: Attach hooks to the Docker event bus to monitor for unexpected container exits during tests.
- **`ContainerStatsSampler`**: Poll `docker stats` dynamically for resource reporting in E2E outputs.