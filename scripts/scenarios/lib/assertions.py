"""Test assertion helpers for ATProto scenario scripts.

Provides clean assertion functions that raise AssertionError on failure,
with descriptive messages for scenario step reporting.
"""

from __future__ import annotations

from typing import Any

from .client import XrpcError


def assert_success(response: dict | Any, operation: str) -> dict:
    """Assert that an XRPC response indicates success (no 'error' key)."""
    if isinstance(response, dict) and "error" in response:
        raise AssertionError(
            f"{operation} failed: error={response.get('error')}, message={response.get('message', response)}"
        )
    return response


def assert_contains(response: dict, key: str, expected: Any = None, operation: str = "") -> Any:
    """Assert that a response dict contains a key (and optionally a specific value)."""
    if key not in response:
        raise AssertionError(
            f"{operation}: key '{key}' not found in response. Keys: {list(response.keys())}"
        )
    if expected is not None and response[key] != expected:
        raise AssertionError(
            f"{operation}: key '{key}' expected {expected!r}, got {response[key]!r}"
        )
    return response[key]


def assert_status(response: dict, expected_status: int, operation: str = "") -> None:
    """Assert that a response has a specific status code (for raw HTTP checks)."""
    actual = response.get("status", response.get("code", 0))
    if actual != expected_status:
        raise AssertionError(
            f"{operation}: expected status {expected_status}, got {actual}"
        )


def assert_error(response: dict, expected_error: str, operation: str = "") -> None:
    """Assert that a response contains a specific error code (for negative tests)."""
    actual_error = response.get("error", "")
    if actual_error != expected_error:
        raise AssertionError(
            f"{operation}: expected error '{expected_error}', got '{actual_error}'. Response: {response}"
        )


def assert_xrpc_raises(
    method_desc: str,
    expected_error: str | None,
    func,
    *args,
    **kwargs,
) -> XrpcError:
    """Call func and assert it raises XrpcError. Returns the caught error for inspection.

    Usage:
        err = assert_xrpc_raises("createRecord with bad input", "InvalidRecord", client.create_record, ...)
    """
    try:
        func(*args, **kwargs)
        raise AssertionError(f"{method_desc}: expected XrpcError but call succeeded")
    except XrpcError as exc:
        if expected_error is not None:
            body = exc.body if isinstance(exc.body, dict) else {}
            actual = body.get("error", "")
            if actual != expected_error:
                raise AssertionError(
                    f"{method_desc}: expected error '{expected_error}', got '{actual}' (status={exc.status})"
                ) from exc
        return exc
