import type { DefaultTheme } from 'vitepress'

export const sidebarConfig: DefaultTheme.Sidebar = [
  {
    text: '01 Getting Started',
    collapsed: false,
    items: [
      { text: 'Overview', link: '/01-getting-started/overview' },
      { text: 'Architecture Overview', link: '/01-getting-started/architecture-overview' },
      { text: 'Codebase Map', link: '/01-getting-started/codebase-map' },
      { text: 'Request Lifecycle', link: '/01-getting-started/request-lifecycle' },
      { text: 'Setup', link: '/01-getting-started/setup' }
    ]
  },
  {
    text: '02 Core Concepts',
    collapsed: false,
    items: [
      { text: 'AT Protocol Basics', link: '/02-core-concepts/atproto-basics' },
      { text: 'CBOR and CAR', link: '/02-core-concepts/cbor-and-car' },
      { text: 'Merkle Search Trees', link: '/02-core-concepts/mst-trees' },
      { text: 'Cryptography', link: '/02-core-concepts/cryptography' },
      { text: 'PLC Directory', link: '/02-core-concepts/plc-directory' },
      { text: 'DID Document Updates', link: '/02-core-concepts/did-document-updates' },
      {
        text: 'Article Series: IPLD & Multiformats',
        collapsed: false,
        items: [
          { text: 'Series Overview', link: '/02-core-concepts/ipld-foundations/' },
          { text: 'IPLD Data Model & Merkle DAGs', link: '/02-core-concepts/ipld-foundations/ipld-data-model-and-merkle-dags' },
          { text: 'CBOR & DAG-CBOR', link: '/02-core-concepts/ipld-foundations/cbor-and-dag-cbor' },
          { text: 'CIDs & Multiformats', link: '/02-core-concepts/ipld-foundations/cids-and-multiformats' },
          { text: 'CAR Files', link: '/02-core-concepts/ipld-foundations/car-files' },
          { text: "ATProto's IPLD Profile", link: '/02-core-concepts/ipld-foundations/atproto-ipld-profile' }
        ]
      },
      { text: 'Deep Dive: Repository Data Structures', link: '/02-core-concepts/repository-data-structures-walkthrough' },
      { text: 'Deep Dive: Protocol Flow', link: '/02-core-concepts/protocol-flow-walkthrough' },
      { text: 'Deep Dive: Cryptography', link: '/02-core-concepts/cryptography-in-practice' },
      { text: 'Deep Dive: PLC Operations', link: '/02-core-concepts/plc-operation-walkthrough' },
      { text: 'Deep Dive: DID Updates', link: '/02-core-concepts/did-update-walkthrough' }
    ]
  },
  {
    text: '03 Application Layer',
    collapsed: false,
    items: [
      { text: 'Services Overview', link: '/03-application-layer/services-overview' },
      { text: 'PDS Application', link: '/03-application-layer/pds-application' },
      { text: 'Account Service', link: '/03-application-layer/account-service' },
      { text: 'Record Service', link: '/03-application-layer/record-service' },
      { text: 'Blob Service', link: '/03-application-layer/blob-service' },
      { text: 'Repository Service', link: '/03-application-layer/repository-service' },
      { text: 'Relay Service', link: '/03-application-layer/relay-service' },
      { text: 'Admin Service', link: '/03-application-layer/admin-service' },
      { text: 'Deep Dive: Runtime Flow', link: '/03-application-layer/runtime-flow-walkthrough' }
    ]
  },
  {
    text: '04 Network Layer',
    collapsed: false,
    items: [
      { text: 'HTTP Server', link: '/04-network-layer/http-server' },
      { text: 'XRPC Dispatch', link: '/04-network-layer/xrpc-dispatch' },
      { text: 'Method Registry', link: '/04-network-layer/method-registry' },
      { text: 'Domain Methods', link: '/04-network-layer/domain-methods' },
      { text: 'Auth Helpers', link: '/04-network-layer/auth-helpers' },
      { text: 'Error Handling', link: '/04-network-layer/error-handling' },
      { text: 'Rate Limiting', link: '/04-network-layer/rate-limiting' },
      { text: 'Request Throttling', link: '/04-network-layer/request-throttling' },
      { text: 'DoS Protection', link: '/04-network-layer/dos-protection' },
      { text: 'Input Validation', link: '/04-network-layer/input-validation' }
    ]
  },
  {
    text: '05 Database Layer',
    collapsed: false,
    items: [
      { text: 'SQLite Architecture', link: '/05-database-layer/sqlite-architecture' },
      { text: 'Actor Databases', link: '/05-database-layer/actor-databases' },
      { text: 'Service Databases', link: '/05-database-layer/service-databases' },
      { text: 'WAL Mode', link: '/05-database-layer/wal-mode' },
      { text: 'Migrations', link: '/05-database-layer/migrations' },
      { text: 'Migration Strategy', link: '/05-database-layer/migration-strategy' },
      { text: 'Migration Rollback', link: '/05-database-layer/migration-rollback' },
      { text: 'Zero-Downtime Migrations', link: '/05-database-layer/zero-downtime-migrations' },
      { text: 'Data Integrity', link: '/05-database-layer/data-integrity' }
    ]
  },
  {
    text: '06 Authentication',
    collapsed: false,
    items: [
      { text: 'JWT Tokens', link: '/06-authentication/jwt-tokens' },
      { text: 'OAuth 2.0 with DPoP', link: '/06-authentication/oauth2-dpop' },
      { text: 'Email & Verification', link: '/06-authentication/email-and-verification' },
      { text: 'TOTP & WebAuthn', link: '/06-authentication/totp-webauthn' },
      { text: 'Key Rotation', link: '/06-authentication/key-rotation' },
      { text: 'Secrets Management', link: '/06-authentication/secrets-management' },
      { text: 'Security Best Practices', link: '/06-authentication/security-best-practices' }
    ]
  },
  {
    text: '07 Repository Protocol',
    collapsed: false,
    items: [
      { text: 'Repository Basics', link: '/07-repository-protocol/repository-basics' },
      { text: 'CBOR Serialization', link: '/07-repository-protocol/cbor-serialization' },
      { text: 'CID and Hashing', link: '/07-repository-protocol/cid-and-hashing' },
      { text: 'CAR Format', link: '/07-repository-protocol/car-format' },
      { text: 'Blob Storage', link: '/07-repository-protocol/blob-storage' },
      { text: 'Blob Lifecycle', link: '/07-repository-protocol/blob-lifecycle' },
      { text: 'Blob Optimization', link: '/07-repository-protocol/blob-optimization' },
      { text: 'Blob Garbage Collection', link: '/07-repository-protocol/blob-garbage-collection' },
      { text: 'Blob Quotas', link: '/07-repository-protocol/blob-quotas' }
    ]
  },
  {
    text: '08 Sync & Firehose',
    collapsed: false,
    items: [
      { text: 'Firehose Overview', link: '/08-sync-firehose/firehose-overview' },
      { text: 'Deep Dive: Firehose Flow', link: '/08-sync-firehose/firehose-flow-walkthrough' },
      { text: 'WebSocket Server', link: '/08-sync-firehose/websocket-server' },
      { text: 'Commit Broadcasting', link: '/08-sync-firehose/commit-broadcasting' },
      { text: 'Backpressure', link: '/08-sync-firehose/backpressure' },
      { text: 'Event Ordering', link: '/08-sync-firehose/event-ordering' },
      { text: 'Event Replay', link: '/08-sync-firehose/event-replay' },
      { text: 'Reconnection Strategy', link: '/08-sync-firehose/reconnection-strategy' },
      { text: 'Reliability Guarantees', link: '/08-sync-firehose/reliability-guarantees' },
      { text: 'Firehose Rate Limiting', link: '/08-sync-firehose/firehose-rate-limiting' }
    ]
  },
  {
    text: '09 Platform Compatibility',
    collapsed: false,
    items: [
      { text: 'macOS & Linux', link: '/09-platform-compatibility/macos-linux' },
      { text: 'Compatibility Layer', link: '/09-platform-compatibility/compatibility-layer' },
      { text: 'ARC Runtime', link: '/09-platform-compatibility/arc-runtime' },
      { text: 'Network Transport', link: '/09-platform-compatibility/network-transport' }
    ]
  },
  {
    text: '10 Tutorials',
    collapsed: false,
    items: [
      { text: 'Tutorials Overview', link: '/10-tutorials/index' },
      { text: 'Tutorial 1: Hello PDS', link: '/10-tutorials/tutorial-1-hello-pds' },
      { text: 'Tutorial 2: Accounts', link: '/10-tutorials/tutorial-2-accounts' },
      { text: 'Tutorial 3: Records', link: '/10-tutorials/tutorial-3-records' },
      { text: 'Tutorial 4: Authentication', link: '/10-tutorials/tutorial-4-auth' },
      { text: 'Tutorial 5: Firehose', link: '/10-tutorials/tutorial-5-firehose' },
      { text: 'Tutorial 6: Deployment', link: '/10-tutorials/tutorial-6-deployment' },
      { text: 'Tutorial 7: Objective-J UI', link: '/10-tutorials/tutorial-7-objective-j-ui' },
      { text: 'Tutorial 8: Endpoint Workflow', link: '/10-tutorials/tutorial-8-endpoint-workflow' }
    ]
  },
  {
    text: '11 Reference',
    collapsed: false,
    items: [
      { text: 'API Reference', link: '/11-reference/api-reference' },
      { text: 'CLI Reference', link: '/11-reference/cli-reference' },
      { text: 'Config Reference', link: '/11-reference/config-reference' },
      { text: 'Explorer, OpenAPI & UI', link: '/11-reference/explorer-openapi-ui' },
      { text: 'Testing Map', link: '/11-reference/testing-map' },
      { text: 'Test Organization', link: '/11-reference/test-organization' },
      { text: 'Property-Based Testing', link: '/11-reference/property-based-testing' },
      { text: 'E2E Testing', link: '/11-reference/e2e-testing' },
      { text: 'Test Coverage Goals', link: '/11-reference/test-coverage-goals' },
      { text: 'Security Audit Guide', link: '/11-reference/security-audit-guide' },
      { text: 'PLC Server Operations', link: '/11-reference/plc-server-operations' },
      { text: 'PLC Failover', link: '/11-reference/plc-failover' },
      { text: 'Logging Strategy', link: '/11-reference/logging-strategy' },
      { text: 'Metrics Collection', link: '/11-reference/metrics-collection' },
      { text: 'Performance Monitoring', link: '/11-reference/performance-monitoring' },
      { text: 'Alerting', link: '/11-reference/alerting' },
      { text: 'Troubleshooting', link: '/11-reference/troubleshooting' }
    ]
  },
  {
    text: '12 Diagrams',
    collapsed: false,
    items: [
      { text: 'Diagram Reference', link: '/12-diagrams/index' }
    ]
  }
]
