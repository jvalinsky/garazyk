"""Garazyk ATProto shared script library.

This package is imported directly from the repository checkout by demo,
scenario, and smoke-test scripts. Re-exporting the common helpers here keeps
call sites short while preserving module boundaries for client transport,
fixtures, reporting, seeding, and service configuration.
"""

from .client import XrpcClient, XrpcError
from .assertions import assert_success, assert_contains, assert_status, assert_error
from .characters import Character, CHARACTERS, get_character, get_characters_by_role
from .report import ScenarioResult, StepResult, StepStatus
from .seed import (
    create_account_or_login,
    create_record_idempotent,
    get_convo_for_members,
    get_messages,
    get_pds_admin_token,
    list_convos,
    now_iso,
    send_message,
    wait_for_http,
    wait_for_server,
)
from .config import (
    SERVICE_PORTS,
    SERVICE_URLS,
    SERVICE_BINARIES,
    SERVICE_HEALTH_PATHS,
    service_url,
    service_health_url,
    find_project_root,
    find_build_dir,
    PDS_ADMIN_PASSWORD,
    PDS_MASTER_SECRET,
    APPVIEW_ADMIN_SECRET,
    UI_ADMIN_PASSWORD,
    DEFAULT_ACCOUNTS,
    DEFAULT_POSTS_TEMPLATES,
)

__all__ = [
    # Client
    "XrpcClient",
    "XrpcError",
    # Assertions
    "assert_success",
    "assert_contains",
    "assert_status",
    "assert_error",
    # Characters
    "Character",
    "CHARACTERS",
    "get_character",
    "get_characters_by_role",
    # Report
    "ScenarioResult",
    "StepResult",
    "StepStatus",
    # Seed helpers
    "create_account_or_login",
    "create_record_idempotent",
    "get_convo_for_members",
    "get_messages",
    "get_pds_admin_token",
    "list_convos",
    "now_iso",
    "send_message",
    "wait_for_http",
    "wait_for_server",
    # Config
    "SERVICE_PORTS",
    "SERVICE_URLS",
    "SERVICE_BINARIES",
    "SERVICE_HEALTH_PATHS",
    "service_url",
    "service_health_url",
    "find_project_root",
    "find_build_dir",
    "PDS_ADMIN_PASSWORD",
    "PDS_MASTER_SECRET",
    "APPVIEW_ADMIN_SECRET",
    "UI_ADMIN_PASSWORD",
    "DEFAULT_ACCOUNTS",
    "DEFAULT_POSTS_TEMPLATES",
]
