# Mega Plan Risk Scores

Higher change safety means the work can ship and roll back in smaller slices.

| Candidate                            | Risk | Drag | Tests | Safety | Payoff | Result |
| ------------------------------------ | ---: | ---: | ----: | -----: | -----: | ------ |
| Dashboard/Admin mutation security    |    5 |    4 |     5 |      4 |      5 | P0     |
| XRPC ownership and contract coverage |    5 |    4 |     5 |      4 |      5 | P0     |
| HTTP aggregate deadline              |    5 |    3 |     5 |      4 |      5 | P0     |
| Lexicon generator consolidation      |    5 |    4 |     5 |      4 |      5 | P0     |
| AppView migrations                   |    5 |    5 |     5 |      3 |      5 | P1     |
| Security regression fixtures         |    4 |    3 |     5 |      5 |      5 | P1     |
| PLC upgrade atomicity                |    4 |    4 |     5 |      3 |      4 | P1     |
| Deno repository split                |    4 |    5 |     5 |      2 |      5 | P1     |
| Relay product decision               |    4 |    5 |     4 |      2 |      5 | P1     |
| Admin UI structure/accessibility     |    4 |    5 |     4 |      3 |      4 | P1     |
| Incremental public sync              |    4 |    4 |     4 |      2 |      5 | P2     |
| Objective-C decomposition            |    3 |    5 |     4 |      2 |      4 | P2     |
| Generated NSID constants             |    2 |    4 |     5 |      4 |      4 | P2     |
| WASM capability closure              |    2 |    4 |     4 |      3 |      3 | P2     |

Dependencies override score order: generator work precedes NSID constants;
migration safety precedes pooling; external repos synchronize before deletion.
