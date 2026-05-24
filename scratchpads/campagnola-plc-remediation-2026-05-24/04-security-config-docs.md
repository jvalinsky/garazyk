# Security, Config, And Docs

## Checklist

- [ ] Replace reflected credentialed CORS with public non-credentialed CORS by default.
- [ ] Gate `Access-Control-Allow-Credentials` and `Access-Control-Allow-Private-Network` behind explicit configuration.
- [ ] Validate `verificationMethods` as syntactically valid `did:key` strings.
- [ ] Keep rotation keys limited to supported k256/p256 curves.
- [ ] Fix P-256 uncompressed key compression parity to use the final Y byte.
- [ ] Add host-aware `PLCReplicaServer` initializer.
- [ ] Make campagnola `--host` apply in replica mode.
- [ ] Require `--database` or explicit `--in-memory` for `serve`.
- [ ] Replace filler HeaderDoc with useful public API docs.
- [ ] Move operational literals into documented constants.
- [ ] Reduce full CBOR/hash operation logs from INFO to DEBUG or remove them.

## Mini-Prompts

- Review public HTTP headers and config defaults as if campagnola is internet-facing.

