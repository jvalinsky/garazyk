# ATProto PDS Architecture Diagrams

## System Overview

```mermaid
graph TB
    subgraph "User Layer"
        Browser[Web Browser]
        CLI[Command Line Interface]
    end

    subgraph "Web Server Layer"
        HTTP[HTTP Server<br/>Port 2583]
        Explore[Explore Handler]
        API[API Endpoints<br/>16 total]
    end

    subgraph "Application Layer"
        PDS[PDS Controller]
        DB[(SQLite Database<br/>Accounts/Records/Blocks)]
        Cache[Explore Cache<br/>DID/PLC/Account TTL]
    end

    subgraph "External Services"
        PLC[PLC Directory<br/>Identity Resolution]
        DID[DID Resolvers]
    end

    Browser --> HTTP
    CLI --> HTTP
    HTTP --> Explore
    HTTP --> API
    Explore --> PDS
    API --> PDS
    PDS --> DB
    PDS --> Cache
    PDS --> PLC
    PDS --> DID

    style Browser fill:#e1f5fe
    style CLI fill:#e1f5fe
    style HTTP fill:#fff3e0
    style Explore fill:#fff3e0
    style API fill:#fff3e0
    style PDS fill:#e8f5e8
    style DB fill:#e8f5e8
    style Cache fill:#e8f5e8
    style PLC fill:#ffebee
    style DID fill:#ffebee
```

## OpenAPI Auto-Generation Flow

```mermaid
graph TD
    subgraph "Code Metadata"
        EndpointDesc[APIEndpointDescriptor<br/>path, method, summary]
        ParamDesc[APIParameterDescriptor<br/>name, type, required]
        ResponseDesc[APIResponseDescriptor<br/>statusCode, schemaRef]
    end

    subgraph "Generation Process"
        Generator[generateOpenAPISpec<br/>Objective-C Method]
        JSONSpec[JSON OpenAPI Spec<br/>NSDictionary]
        YAMLSerializer[jsonToYAML<br/>Custom Serializer]
    end

    subgraph "Output"
        YAMLFile[openapi.yaml<br/>Downloadable Spec]
        JSONFile[openapi.json<br/>Swagger UI Input]
        SwaggerUI[Interactive Docs<br/>/explore/api/docs]
    end

    EndpointDesc --> Generator
    ParamDesc --> Generator
    ResponseDesc --> Generator
    Generator --> JSONSpec
    JSONSpec --> YAMLSerializer
    YAMLSerializer --> YAMLFile
    JSONSpec --> JSONFile
    JSONFile --> SwaggerUI

    style EndpointDesc fill:#e3f2fd
    style ParamDesc fill:#e3f2fd
    style ResponseDesc fill:#e3f2fd
    style Generator fill:#fff3e0
    style JSONSpec fill:#fff3e0
    style YAMLSerializer fill:#fff3e0
    style YAMLFile fill:#e8f5e8
    style JSONFile fill:#e8f5e8
    style SwaggerUI fill:#e8f5e8
```

## Frontend Performance Architecture

```mermaid
graph TD
    subgraph "Browser Cache Layer"
        CacheMap[Map Cache<br/>TTL-based storage]
        CacheTTL[CACHE_TTL<br/>did:5min, plc:10min<br/>describe:2min, etc.]
    end

    subgraph "API Client Layer"
        API[API Object<br/>16 methods]
        CacheUtil[getCachedOrFetch<br/>Cache wrapper]
    end

    subgraph "UI Layer"
        UI[ui.js<br/>Event handlers]
        Parallel[Promise.all<br/>Parallel API calls]
    end

    subgraph "Performance Optimizations"
        Instant[Instant repeat clicks<br/>via cache hits]
        ParallelLoad[2.4x faster loading<br/>via Promise.all]
        RateLimit[Rate limit protection<br/>via TTL cache]
    end

    CacheMap --> CacheUtil
    CacheTTL --> CacheUtil
    CacheUtil --> API
    API --> UI
    UI --> Parallel
    Parallel --> Instant
    Parallel --> ParallelLoad
    CacheUtil --> RateLimit

    style CacheMap fill:#e8f5e8
    style CacheTTL fill:#e8f5e8
    style API fill:#fff3e0
    style CacheUtil fill:#fff3e0
    style UI fill:#e3f2fd
    style Parallel fill:#e3f2fd
    style Instant fill:#c8e6c9
    style ParallelLoad fill:#c8e6c9
    style RateLimit fill:#c8e6c9
```

## API Endpoint Organization

```mermaid
graph TD
    subgraph "Account Management"
        Accounts[GET /accounts<br/>operationId: listAccounts]
        AccountDetails[GET /account-details<br/>operationId: getAccountDetails]
    end

    subgraph "Repository Operations"
        Repositories[GET /repositories<br/>operationId: listRepositories]
        Describe[GET /describe<br/>operationId: describeRepository]
    end

    subgraph "Record Management"
        AccountRecords[GET /account-records<br/>operationId: listAccountRecords]
        Record[GET /record<br/>operationId: getRecord]
        RecordDetails[GET /record-details<br/>operationId: getRecordDetails]
        CreateRecord[POST /create-record<br/>operationId: createRecord]
    end

    subgraph "Identity Services"
        Lookup[GET /lookup<br/>operationId: resolveIdentity]
        DID[GET /did<br/>operationId: getDidDocument]
        PlcLog[GET /plc-log<br/>operationId: getPlcLog]
    end

    subgraph "Content Services"
        CidDecode[GET /cid-decode<br/>operationId: decodeCid]
        CidInfo[GET /cid-info<br/>operationId: getCidInfo]
        Blob[GET /blob<br/>operationId: getBlob]
    end

    subgraph "Collection Management"
        Collections[GET /collections<br/>operationId: listCollections]
    end

    Accounts --> A[Tags: Accounts]
    AccountDetails --> A
    Repositories --> B[Tags: Repositories]
    Describe --> B
    AccountRecords --> C[Tags: Records]
    Record --> C
    RecordDetails --> C
    CreateRecord --> C
    Lookup --> D[Tags: Identity]
    DID --> D
    PlcLog --> D
    CidDecode --> E[Tags: Content]
    CidInfo --> E
    Blob --> E
    Collections --> F[Tags: Collections]

    style A fill:#e3f2fd
    style B fill:#e3f2fd
    style C fill:#e3f2fd
    style D fill:#e3f2fd
    style E fill:#e3f2fd
    style F fill:#e3f2fd
```

## Data Flow: Account Loading

```mermaid
sequenceDiagram
    participant User
    participant Browser
    participant Cache
    participant Server
    participant DB

    User->>Browser: Click account
    Browser->>Browser: Show loading state
    Browser->>Cache: Check did:${did}
    alt Cache hit
        Cache-->>Browser: Return cached DID doc
        Browser->>Browser: Update UI instantly
    else Cache miss
        Browser->>Server: GET /api/did?did=${did}
        Server->>DB: Query DID document
        DB-->>Server: Return document
        Server-->>Browser: JSON response
        Browser->>Cache: Store with 5min TTL
    end

    Browser->>Browser: Start parallel calls

    par Parallel API calls
        Browser->>Server: GET /api/getPlcLog
        Server->>DB: Query PLC operations
        DB-->>Server: Return operations
        Server-->>Browser: PLC log data

        Browser->>Server: GET /api/describe
        Server->>DB: Query repository info
        DB-->>Server: Collections & counts
        Server-->>Browser: Repository data
    end

    Browser->>Browser: Render all sections
    Browser->>User: Display complete account view
```

## Component Dependencies

```mermaid
graph TD
    subgraph "Core Server"
        Main[main.m<br/>Entry point]
        PDS[PDSController<br/>Business logic]
        DB[PDSDatabase<br/>Data persistence]
    end

    subgraph "Web Interface"
        HTTP[HttpServer<br/>HTTP handling]
        Explore[ExploreHandler<br/>Web UI routes]
        Cache[ExploreCache<br/>TTL caching]
    end

    subgraph "API Generation"
        Descriptor[APIDescriptor classes<br/>Metadata models]
        Generator[OpenAPI generator<br/>Spec creation]
        Serializer[YAML serializer<br/>Format conversion]
    end

    subgraph "Frontend Assets"
        HTML[index.html<br/>UI structure]
        CSS[style.css<br/>Styling]
        JS[JavaScript modules<br/>api.js, ui.js, etc.]
    end

    Main --> HTTP
    HTTP --> Explore
    Explore --> PDS
    Explore --> Cache
    PDS --> DB

    Explore --> Descriptor
    Descriptor --> Generator
    Generator --> Serializer

    Explore --> HTML
    Explore --> CSS
    Explore --> JS

    style Main fill:#e8f5e8
    style PDS fill:#e8f5e8
    style DB fill:#e8f5e8
    style HTTP fill:#fff3e0
    style Explore fill:#fff3e0
    style Cache fill:#fff3e0
    style Descriptor fill:#e3f2fd
    style Generator fill:#e3f2fd
    style Serializer fill:#e3f2fd
    style HTML fill:#fce4ec
    style CSS fill:#fce4ec
    style JS fill:#fce4ec
```

## Performance Timeline

```mermaid
gantt
    title UI Loading Performance Timeline
    dateFormat  HH:mm:ss
    axisFormat %M:%S

    section Before (Sequential)
    DID Document Load    :done, 0, 200ms
    PLC Operations Load  :done, 200ms, 200ms
    Repository Describe   :done, 400ms, 200ms
    Total Load Time       :done, 0, 600ms

    section After (Parallel + Cache)
    Cache Check (Instant) :done, 0, 10ms
    Parallel API Calls    :done, 10ms, 240ms
    Total Load Time       :done, 0, 250ms
    Performance Gain      :done, 0, 350ms
```

## Cache Strategy Overview

```mermaid
stateDiagram-v2
    [*] --> API_Call_Requested
    API_Call_Requested --> Cache_Check: Check cache key

    Cache_Check --> Cache_Hit: Data exists & fresh
    Cache_Check --> Cache_Miss: Data missing or stale

    Cache_Hit --> Return_Cached_Data
    Return_Cached_Data --> [*]

    Cache_Miss --> Network_Request: Make API call
    Network_Request --> Store_In_Cache: On success
    Network_Request --> Return_Error: On failure

    Store_In_Cache --> Return_Fresh_Data
    Return_Error --> [*]
    Return_Fresh_Data --> [*]

    note right of Cache_Check : TTL varies by endpoint:\n• DID docs: 5min\n• PLC logs: 10min\n• Records: 2-5min
    note right of Network_Request : Protects against\nplc.directory rate limits

## Related Documentation

### Architecture Documents
- [README.md](README.md) - Architecture documentation index
- [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) - Component analysis for diagrams above

### Diagram Documents
- [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID.md) - Protocol flow diagrams
- [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE.md) - Diagram selection guide
- [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS.md) - Development process diagrams

### Related Guides
- [../guides/DEVELOPER_GUIDE.md](../guides/DEVELOPER_GUIDE.md) - Developer onboarding guide
```