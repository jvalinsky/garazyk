# Lexicon Schema Notes

- XRPC methods are lexicon JSON files with `type` of `query`, `procedure`, or `subscription`.
- The `id` field is the canonical method ID (fallback to file path if missing).
- `defs.json` files usually define shared record types, not RPC methods.
