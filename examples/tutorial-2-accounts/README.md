# Tutorial 2: Account Management

This example demonstrates account creation and management with JWT token generation.

## Building

### macOS

```bash
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)
```

### Linux (GNUstep)

```bash
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Running

```bash
./build/tutorial-2-accounts
```

Or on Linux:

```bash
./build-linux/tutorial-2-accounts
```

## Testing

In another terminal, test the endpoints:

### Create Account

```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "alice@example.com",
    "password": "secure_password",
    "handle": "alice"
  }' | jq .
```

Expected response:

```json
{
  "did": "did:plc:...",
  "handle": "alice",
  "email": "alice@example.com",
  "accessJwt": "eyJ...",
  "refreshJwt": "eyJ..."
}
```

### Login

```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "alice",
    "password": "secure_password"
  }' | jq .
```

Expected response:

```json
{
  "did": "did:plc:...",
  "handle": "alice",
  "email": "alice@example.com",
  "accessJwt": "eyJ...",
  "refreshJwt": "eyJ..."
}
```

### Describe Server

```bash
curl http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .
```

Expected response:

```json
{
  "did": "did:web:localhost:2583",
  "availableUserDomains": ["localhost"],
  "inviteCodeRequired": false,
  "phoneNumberRequired": false
}
```

## Troubleshooting

### Port already in use

```bash
lsof -i :2583
kill -9 <PID>
```

### Build errors

```bash
rm -rf build
mkdir build && cd build
cmake ..
make
```

### Database errors

```bash
rm -rf ~/.tutorial-2-accounts/
./build/tutorial-2-accounts
```

## What's Included

- `Account.h/m` — Account data model
- `AccountRepository.h/m` — SQLite-based account storage
- `SimpleJWTMinter.h/m` — JWT token generation
- `AccountService.h/m` — Account creation and login logic
- `main.m` — HTTP server and XRPC dispatcher

## Next Steps

See [Tutorial 2: Account Management](../../docs/10-tutorials/tutorial-2-accounts.md) for detailed documentation.
