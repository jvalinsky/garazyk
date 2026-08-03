# DASL conformance vectors

Verbatim copy of `fixtures/cbor/` from [hyphacoop/dasl-testing](https://github.com/hyphacoop/dasl-testing),
the conformance suite for the [DASL](https://dasl.ing/) specs. 104 vectors across 11 files.
MIT licensed; declared in `.reuse/dep5`.

Driven by `Garazyk/Tests/Core/DASLConformanceTests.m`.

## Vector format

Each file is a JSON array of objects:

| Field | Meaning |
| --- | --- |
| `type` | `roundtrip`, `invalid_in`, or `invalid_out` |
| `data` | Hex-encoded CBOR bytes |
| `name` | Short label |
| `tags` | Which specs the vector applies to |
| `desc` | Prose explanation |

`roundtrip` means decode then re-encode must reproduce `data` byte for byte. `invalid_in` means
decoding `data` must fail. `invalid_out` means decoding `data` may succeed, but re-encoding the
decoded value must fail.

Tags in use: `basic`, `dag-cbor`, `dasl-cid`, `rfc8949`, `dCBOR`, `CBOR-Core`, `CDE`. Garazyk
tests the `basic`, `dag-cbor` and `dasl-cid` sets — `dCBOR`, `CDE` and the parts of `rfc8949` and
`CBOR-Core` that contradict DAG-CBOR describe *different* CBOR profiles, and several of their
vectors are deliberate inverses of the DAG-CBOR ones (`f93e00` roundtrips under `rfc8949` and is
invalid under `dag-cbor`).

## Refreshing

```bash
for f in cid concat floats indefinite integer_range map_keys numeric_reduction short_form simple tags utf8; do
  curl -sSf -o "Garazyk/Tests/fixtures/dasl-testing/$f.json" \
    "https://raw.githubusercontent.com/hyphacoop/dasl-testing/main/fixtures/cbor/$f.json"
done
```

New vectors that Garazyk fails will surface as test failures rather than being skipped. Known
deviations are listed explicitly in `DASLConformanceTests.m`; anything not on that list is a bug.
