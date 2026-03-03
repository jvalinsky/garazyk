# Product Overview

September is a standards-compliant AT Protocol Personal Data Server (PDS) implementation written in Objective-C for macOS and Linux/GNUstep.

## Core Purpose

Provides a self-hosted personal data server that implements the AT Protocol specifications, enabling users to control their own social data and identity in the decentralized AT Protocol network.

## Key Features

- Full AT Protocol compliance (DAG-CBOR, CAR v1, MST, Firehose)
- OAuth 2.0 with DPoP authentication
- Biometric security with hardware-backed key storage
- Interactive web-based explorer UI
- Auto-generated OpenAPI documentation
- Comprehensive test coverage (1017 tests)

## Executables

- `kaszlak` - PDS CLI tool (main server binary)
- `campagnola` - Standalone PLC directory server

## Default Configuration

- Server port: 2583
- Data directory: `./data/`
- Config file: `config.json`
