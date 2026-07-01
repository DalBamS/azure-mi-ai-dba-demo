"""Configuration loading for the game load driver.

Secrets are NEVER hardcoded. Values come from environment variables (loaded from
a local, git-ignored ``.env``) and, preferably, from Azure Key Vault.

Supported AUTH_MODE values:
    aad-integrated          - DefaultAzureCredential (az login / managed identity)
    aad-service-principal   - AAD_TENANT_ID / AAD_CLIENT_ID / AAD_CLIENT_SECRET
    aad-password            - AAD user UID/PWD via ODBC ActiveDirectoryPassword
    sql                     - SQL auth UID/PWD (LOCAL/DEV ONLY)
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # dotenv optional; env vars may be set another way
    pass


def _get(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _get_int(name: str, default: int) -> int:
    raw = _get(name)
    return int(raw) if raw else default


def _get_bool(name: str, default: bool) -> bool:
    raw = _get(name).lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "on")


def _resolve_secret_from_keyvault(secret_name: str) -> str:
    """Fetch a secret from Azure Key Vault. Returns '' on any failure."""
    vault = _get("KEYVAULT_NAME")
    if not vault or not secret_name:
        return ""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient

        url = f"https://{vault}.vault.azure.net"
        client = SecretClient(vault_url=url, credential=DefaultAzureCredential())
        return client.get_secret(secret_name).value or ""
    except Exception as exc:  # noqa: BLE001 - config path, surface but don't crash import
        print(f"[config] Key Vault secret '{secret_name}' unavailable: {exc}")
        return ""


@dataclass
class Config:
    server: str = ""
    database: str = "gamedb"
    port: int = 1433
    auth_mode: str = "aad-integrated"

    sql_user: str = ""
    sql_password: str = ""

    aad_tenant_id: str = ""
    aad_client_id: str = ""
    aad_client_secret: str = ""

    odbc_driver: str = "ODBC Driver 18 for SQL Server"
    odbc_encrypt: str = "yes"
    odbc_trust_server_cert: str = "no"

    mimic_oledb_set_options: bool = True

    # workload mix / concurrency
    concurrency: int = 8
    duration_seconds: int = 0
    mix_currency_transfer: int = 40
    mix_inventory_update: int = 40
    mix_ranking_query: int = 20

    # data-shape hints (used to pick random ids); resolved lazily from DB if 0
    seed_players: int = field(default=0)
    seed_items_per_player: int = field(default=20)
    seed_season: int = field(default=1)

    @classmethod
    def from_env(cls) -> "Config":
        cfg = cls(
            server=_get("SQLMI_SERVER"),
            database=_get("SQLMI_DATABASE", "gamedb"),
            port=_get_int("SQLMI_PORT", 1433),
            auth_mode=_get("AUTH_MODE", "aad-integrated").lower(),
            sql_user=_get("SQL_USER"),
            sql_password=_get("SQL_PASSWORD"),
            aad_tenant_id=_get("AAD_TENANT_ID"),
            aad_client_id=_get("AAD_CLIENT_ID"),
            aad_client_secret=_get("AAD_CLIENT_SECRET"),
            odbc_driver=_get("ODBC_DRIVER", "ODBC Driver 18 for SQL Server"),
            odbc_encrypt=_get("ODBC_ENCRYPT", "yes"),
            odbc_trust_server_cert=_get("ODBC_TRUST_SERVER_CERT", "no"),
            mimic_oledb_set_options=_get_bool("MIMIC_OLEDB_SET_OPTIONS", True),
            concurrency=_get_int("WORKLOAD_CONCURRENCY", 8),
            duration_seconds=_get_int("WORKLOAD_DURATION_SECONDS", 0),
            mix_currency_transfer=_get_int("WORKLOAD_MIX_CURRENCY_TRANSFER", 40),
            mix_inventory_update=_get_int("WORKLOAD_MIX_INVENTORY_UPDATE", 40),
            mix_ranking_query=_get_int("WORKLOAD_MIX_RANKING_QUERY", 20),
            seed_players=_get_int("SEED_PLAYERS", 0),
            seed_items_per_player=_get_int("SEED_ITEMS_PER_PLAYER", 20),
            seed_season=_get_int("SEED_SEASON", 1),
        )

        # Prefer Key Vault for the SQL password when configured.
        if cfg.auth_mode in ("sql", "aad-password") and not cfg.sql_password:
            cfg.sql_password = _resolve_secret_from_keyvault(
                _get("KEYVAULT_SECRET_SQL_PASSWORD", "sqlmi-admin-password")
            )

        cfg.validate()
        return cfg

    def validate(self) -> None:
        if not self.server:
            raise ValueError("SQLMI_SERVER is required (set it in .env, never hardcode).")
        valid = {"aad-integrated", "aad-service-principal", "aad-password", "sql"}
        if self.auth_mode not in valid:
            raise ValueError(f"AUTH_MODE must be one of {valid}, got '{self.auth_mode}'.")
