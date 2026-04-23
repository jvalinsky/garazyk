# XrpcProxyTests Analysis

## Problem
9 tests are failing in `XrpcProxyTests` indicating proxy routing isn't working as expected. In particular, upstream requests like `ageassurance.begin` and ozone fallback are returning `400 Bad Request` instead of the expected `200 OK`.

## Root Cause
The `XrpcProxy` logic is responsible for forwarding unknown or fallback XRPC methods (like `ageassurance.begin`) to the upstream delegate or configured fallback URL (e.g., an Ozone or AppView instance). If it is returning `400 Bad Request`, it's likely because the local handler registry is intercepting the request and immediately rejecting it due to missing implementation or invalid schema, or the proxy logic itself doesn't properly bypass the local checks for configured proxy endpoints.

## Solution Choices
1. **Adjust local handler routing:** Ensure the fallback proxy kicks in *before* or *instead of* a local 400 Bad Request response when a proxy route is configured.
2. **Update the test mock:** Check if the test proxy environment is correctly initialized and if the mock upstream is actually returning 200 or 400. 

## Decision
We will analyze the `XrpcProxy` routing and fallback logic to determine why `400 Bad Request` is being generated and adjust the `XrpcProxy` or its handler registration so that proxy requests correctly reach their upstream destination instead of being locally rejected.
