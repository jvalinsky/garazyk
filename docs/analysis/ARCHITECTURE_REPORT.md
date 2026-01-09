# Architectural Analysis Report: ATProtoPDS

**Date:** January 09, 2026
**Scope:** `ATProtoPDS/Sources`
**Analyst:** Antigravity (Agentic AI)

## 1. Executive Summary

The `ATProtoPDS` codebase is a modular Objective-C project implementing an AT Protocol Personal Data Server (PDS). While the project structure exhibits clear domain separation (Auth, Database, Network, etc.), the implementation suffers from significant "God Class" anti-patterns in core controllers and database layers.

The project appears to be in a transition state between a monolithic database architecture (`PDSDatabase`) and a single-tenant architecture (`ActorStore`/`PDSDatabasePool`), resulting in code duplication and ambiguity.

## 2. Project Structure Analysis

The `Sources` directory is well-organized by domain:

-   **Admin**: Administrative endpoints and middleware.
-   **App**: Core application logic, configuration, and the main controller (`PDSController`).
-   **Auth**: Authentication utilities (JWT, OAuth2, Crypto).
-   **Blob**: Blob storage handling.
-   **Core**: Fundamental data types (CID, DID, TID).
-   **Database**: Data access layer, containing both monolithic and pooled implementations.
-   **Network**: HTTP server and routing logic.
-   **Repository**: AT Protocol repository structures (MST, CBOR).

This high-level structure is sound and promotes modularity. However, the dependencies between these modules are often tightly coupled via the central `PDSController`.

## 3. Architectural Patterns & Design

### 3.1. Centralized Control (Facade/God Class)
`PDSController` (933 lines) acts as a massive Facade. It coordinates:
-   Server lifecycle (HTTP & WebSocket)
-   Account management (Create, Login, Delete)
-   Repository operations
-   Record management (CRUD)
-   Blob operations
-   Metrics and Health checks

**Impact**: High coupling, difficult to test in isolation, violation of Single Responsibility Principle (SRP).

### 3.2. Data Access Patterns
Two competing patterns exist:
1.  **Monolithic DAO (`PDSDatabase`)**: A single class managing all tables (`accounts`, `repos`, `records`, etc.) in one database.
2.  **Single-Tenant Store (`ActorStore`)**: A per-user database managed by `PDSDatabasePool`.

**Impact**: Schema definitions and CRUD logic are duplicated between `PDSDatabase.m` and `ActorStore.m`. This increases the maintenance burden and risk of inconsistencies.

### 3.3. Singleton Pattern
Used extensively:
-   `PDSController.sharedController`
-   `PDSHealthCheck.sharedInstance`
-   `XrpcDispatcher.sharedDispatcher`
-   `PDSMigrationManager.sharedManager`

**Impact**: Global state makes unit testing difficult and hides dependencies.

## 4. Code Quality & Anti-Patterns

### 4.1. God Classes
-   **`PDSDatabase` (1491 lines)**: Handles connection, schema creation, and all CRUD operations for all entities.
-   **`ActorStore` (1082 lines)**: Similar to `PDSDatabase` but for single-tenant databases. Contains duplicated schema strings and logic.
-   **`PDSController` (933 lines)**: See Section 3.1.

### 4.2. Code Duplication
-   **CID & Base32**: `PDSController` re-implements Base32 encoding/decoding and CID generation, despite `Base32Utils` and `CID` classes existing in `Auth` and `Core` modules respectively.
-   **SQL Schemas**: DDL strings (CREATE TABLE...) are hardcoded in both `PDSDatabase.m` and `ActorStore.m`.

### 4.3. Hardcoded SQL
All SQL queries are hardcoded string literals within the Objective-C code.
-   **Risk**: Maintenance difficulty. Schema changes require searching through large files.
-   **Mitigation**: The code *does* use parameterized queries (`sqlite3_bind_*`), protecting against SQL injection.

## 5. Objective-C Best Practices

-   **ARC**: Proper Automatic Reference Counting usage. No manual `retain`/`release`.
-   **Properties**: Correct use of `@property` and access modifiers.
-   **Modern Syntax**: Usage of object literals (`@[]`, `@{}`) is consistent.
-   **Nullability**: Headers use `NS_ASSUME_NONNULL_BEGIN`/`END`, improving Swift interoperability and compiler checks.
-   **Error Handling**: Consistent use of `NSError **` pattern.
-   **Concurrency**: Uses `dispatch_queue` (GCD) effectively for thread safety (e.g., `cacheQueue` in `PDSDatabase`, `repoQueue` in `PDSController`).

## 6. Recommendations

### 6.1. Refactor `PDSController`
Break it down into specialized service classes:
-   `AccountService`: Handle registration, login, auth.
-   `RepositoryService`: Handle repo updates, MST operations.
-   `DataService` (or `RecordService`): Handle record CRUD.
`PDSController` should only bootstrap these services.

### 6.2. Unify Database Layer
-   Decide on **one** architecture (likely Single-Tenant `ActorStore` given the "Migration" code).
-   Extract SQL schemas and queries into constants or a dedicated `SchemaManager`.
-   Create specific DAOs (e.g., `AccountDAO`, `RepoDAO`) that operate on an `ActorStore` or `PDSDatabase` instance, rather than having all methods in one class.

### 6.3. Eliminate Duplication
-   Replace manual Base32/CID logic in `PDSController` with `Base32Utils` and `CID` classes.
-   Consolidate schema definitions.

### 6.4. Dependency Injection
-   Move away from Singletons where possible. Pass dependencies (like `PDSDatabasePool`) into initializers of services.
