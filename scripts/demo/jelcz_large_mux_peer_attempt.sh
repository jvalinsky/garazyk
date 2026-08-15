#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Attempt to put the catalog MUX (~19GiB) into CA/iroh on jelcz-a, and prove a
# large-but-fitting object peers over iroh to B/C.
set -euo pipefail

A="${JELCZ_A:-http://127.0.0.1:2596}"
B="${JELCZ_B:-http://127.0.0.1:2597}"
C="${JELCZ_C:-http://127.0.0.1:2598}"
URI="${VOD_URI:-at://did:plc:rbvrr34edl5ddpuwcubjiost/place.stream.video/3mipbxjavnf2m}"
LARGE_MB="${LARGE_PEER_MB:-32}"

echo "== disk =="
df -h /Users/jack | tail -1
docker exec streamplace-peership-jelcz-a-1 df -h /var/lib/jelcz | tail -1

echo "== peer session (discover MUX cid/size) =="
curl -fsS --max-time 90 -X POST -H 'content-type: application/json' \
  -d "{\"uri\":\"${URI}\",\"kind\":\"vod\"}" "${A}/demo/streamplace/api/peer" \
  > /tmp/jelcz-peer-session.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/jelcz-peer-session.json"))
mux=None
for o in d.get("objects") or []:
    print(o.get("status"), o.get("size"), o.get("cid"))
    if (o.get("size") or 0) > 1_000_000_000:
        mux=o
open("/tmp/jelcz-mux.json","w").write(json.dumps(mux or {}, indent=2))
if not mux:
    raise SystemExit("no multi-GB mux object in peer session")
print("MUX_CID", mux["cid"])
print("MUX_BYTES", mux["size"])
PY

MUX_CID=$(python3 -c 'import json; print(json.load(open("/tmp/jelcz-mux.json"))["cid"])')
MUX_BYTES=$(python3 -c 'import json; print(json.load(open("/tmp/jelcz-mux.json"))["size"])')

FREE_HOST=$(df -k /Users/jack | awk 'NR==2{print $4}')
FREE_CTR=$(docker exec streamplace-peership-jelcz-a-1 df -k /var/lib/jelcz | awk 'NR==2{print $4}')
NEED_KB=$(( (MUX_BYTES / 1024) + 1024*1024 )) # object + ~1GiB headroom

echo "== MUX ingest feasibility =="
echo "mux_bytes=$MUX_BYTES need_kb=$NEED_KB host_free_kb=$FREE_HOST ctr_free_kb=$FREE_CTR"

MUX_RESULT="skipped"
if (( FREE_CTR < NEED_KB || FREE_HOST < NEED_KB )); then
  MUX_RESULT="blocked-disk"
  echo "REFUSE: cannot put ${MUX_BYTES} byte MUX into CA/iroh with free disk host=${FREE_HOST}KB ctr=${FREE_CTR}KB"
else
  echo "Attempting full MUX download into CA via getVideoBlob (this may take a long time)..."
  # Full GET without Range — only if disk allows.
  if curl -fsS --max-time 3600 -o /tmp/jelcz-mux.bin \
      "${A}/xrpc/place.stream.playback.getVideoBlob?did=did:plc:rbvrr34edl5ddpuwcubjiost&cid=${MUX_CID}"; then
    SIZE=$(wc -c </tmp/jelcz-mux.bin)
    echo "downloaded $SIZE bytes; seeding to A CA+iroh..."
    SEED=$(curl -fsS --max-time 600 -X POST -H 'content-type: application/octet-stream' \
      --data-binary @/tmp/jelcz-mux.bin "${A}/demo/streamplace/api/seed")
    echo "$SEED" | python3 -m json.tool | head -40
    MUX_RESULT="seeded"
    rm -f /tmp/jelcz-mux.bin
  else
    MUX_RESULT="download-failed"
  fi
fi

echo "== large-but-fitting iroh peer proof (${LARGE_MB} MiB) =="
python3 - <<PY
import os
path="/tmp/jelcz-large-peer.bin"
n=${LARGE_MB}*1024*1024
# Deterministic compressible-ish payload with unique header
hdr=f"jelcz-large-peer-{os.getpid()}-{n}\\n".encode()
with open(path,"wb") as f:
    f.write(hdr)
    remain=n-len(hdr)
    chunk=b"garazyk-iroh-large\\n"*4096
    while remain>0:
        take=min(remain,len(chunk))
        f.write(chunk[:take])
        remain-=take
print("wrote", path, "bytes", os.path.getsize(path))
PY

curl -fsS --max-time 300 -X POST -H 'content-type: application/octet-stream' \
  --data-binary @/tmp/jelcz-large-peer.bin "${A}/demo/streamplace/api/seed" \
  > /tmp/jelcz-large-seed.json
python3 -m json.tool < /tmp/jelcz-large-seed.json
LARGE_CID=$(python3 -c 'import json; print(json.load(open("/tmp/jelcz-large-seed.json"))["cid"])')
IROH=$(python3 -c 'import json; print(json.load(open("/tmp/jelcz-large-seed.json")).get("irohProvider") or "")')
python3 -c 'import json; print("fanout", json.dumps(json.load(open("/tmp/jelcz-large-seed.json")).get("meshFanout") or []))'
echo "large_cid=$LARGE_CID iroh=$IROH"

python3 - <<'PY'
import json
fan=json.load(open("/tmp/jelcz-large-seed.json")).get("meshFanout") or []
ok=all(
    r.get("status") in ("peered-verified","already-local")
    and r.get("peerSource") in ("iroh-peer","ca-store","https-peer")
    for r in fan
)
print("fanout_ok", ok, "rows", len(fan))
if not ok or len(fan)<2:
    raise SystemExit(2)
PY

# Confirm B/C serve from CA
for P in "$B" "$C"; do
  curl -fsS --max-time 60 -X POST -H 'content-type: application/json' \
    -d "{\"cid\":\"${LARGE_CID}\",\"provider\":\"${IROH}\",\"did\":\"did:web:jelcz.local\"}" \
    "${P}/demo/streamplace/api/pull-peer" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status"), d.get("peerSource"), d.get("size"))'
done

rm -f /tmp/jelcz-large-peer.bin

echo
echo "SUMMARY mux_result=${MUX_RESULT} mux_cid=${MUX_CID} mux_bytes=${MUX_BYTES} large_cid=${LARGE_CID} large_mb=${LARGE_MB}"
if [[ "$MUX_RESULT" == "blocked-disk" ]]; then
  echo "MUX CA/iroh ingest not possible on this host without freeing >$(( NEED_KB / 1024 / 1024 )) GiB."
  exit 0
fi
if [[ "$MUX_RESULT" != "seeded" ]]; then
  exit 1
fi
