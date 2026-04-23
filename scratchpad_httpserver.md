# PDSHttpServerBuilderTests Analysis

## Problem
4 tests are failing in `PDSHttpServerBuilderTests` because static UI routes (`/ui`, etc.) and well-known routes (`.well-known/oauth-authorization-server`) are returning `404 Not Found`.

## Root Cause
The `PDSHttpServerBuilder` may have lost the configuration blocks that register these static file servers or static JSON endpoints when constructing the `HttpServer`.

## Solution Choices
1. **Restore missing route handlers:** Add the missing route registrations inside `PDSHttpServerBuilder.m`.
2. **Update tests:** If these routes were intentionally removed (e.g., UI separated from PDS), then the tests should be removed. 

## Decision
The PDS still serves these files historically (like the Objective-J UI and oauth files). I will re-add the static UI routes and well-known routes to `PDSHttpServerBuilder.m` so the HTTP server mounts them properly.
