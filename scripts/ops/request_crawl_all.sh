#!/bin/bash
# request_crawl_all.sh
# Request crawl on all known ATProto relays for a given PDS

PDS_HOSTNAME="pds.garazyk.xyz"
RELAYS=(
    "relay.bas.sh"
    "bsky.network"
    "europe.firehose.network"
    "relay1.us-east.bsky.network"
    "relay1.us-west.bsky.network"
    "frankfurt.firehose.stream"
    "london.firehose.stream"
    "asia.firehose.network"
    "jetstream2.us-east.bsky.network"
    "relay3.fr.hose.cam"
    "northamerica.firehose.network"
    "jetstream1.us-east.fire.hose.cam"
    "jetstream2.us-west.bsky.network"
    "chennai.firehose.stream"
    "nyc.firehose.stream"
    "jetstream2.fr.hose.cam"
    "jetstream1.us-west.bsky.network"
    "jet.firehose.stream"
    "relay.xero.systems"
    "jetstream1.us-east.bsky.network"
    "relay.fire.hose.cam"
    "relay.waow.tech"
    "sfo.firehose.stream"
    "jetstream1.xero.systems"
    "jetstream.waow.tech"
    "zlay.waow.tech"
    "relay.upcloud.world"
    "jetstream.fire.hose.cam"
    "atproto.africa"
    "relay.feeds.blue"
    "relay.t4tlabs.net"
)

for relay in "${RELAYS[@]}"; do
    echo "Requesting crawl on $relay..."
    curl -X POST "https://$relay/xrpc/com.atproto.sync.requestCrawl" \
         -H "Content-Type: application/json" \
         -d "{\"hostname\": \"$PDS_HOSTNAME\"}" \
         --max-time 5 \
         --silent \
         --output /dev/null
    
    if [ $? -eq 0 ]; then
        echo "Successfully sent request to $relay"
    else
        echo "Failed to send request to $relay"
    fi
done
