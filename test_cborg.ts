import { decode } from "npm:cborg";
// create a deeply nested array in CBOR
// 0x81 is array of length 1.
const depth = 20000;
const payload = new Uint8Array(depth + 1);
payload.fill(0x81, 0, depth);
payload[depth] = 0x01; // number 1 at the deepest level
try {
  decode(payload);
  console.log("Decoded successfully?");
} catch (e) {
  console.log("Caught error:", e.name, e.message);
}
