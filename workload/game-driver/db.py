"""Connection helpers for the game load driver.

Builds a pyodbc connection for each supported AUTH_MODE and, when
``MIMIC_OLEDB_SET_OPTIONS`` is enabled, applies the SET options that the
production C++/MSOLEDBSQL (OLE DB) client uses by default.

Why this matters for the demo
------------------------------
SSMS connects with ``ARITHABORT ON`` while OLE DB apps default to
``ARITHABORT OFF``. Different SET options produce *separate* plan-cache
entries, which is the classic root cause of "runs fast in SSMS, slow from the
app" plan-regression incidents. Reproducing the production SET options makes
the runtime demo (C: plan regression) authentic.
"""

from __future__ import annotations

import struct

import pyodbc

from config import Config

# ODBC connection attribute for AAD access tokens.
_SQL_COPT_SS_ACCESS_TOKEN = 1256
_AAD_SCOPE = "https://database.windows.net/.default"

# OLE DB (MSOLEDBSQL) default session SET options. ARITHABORT OFF is the key
# difference from SSMS and the trigger for the plan-regression demo.
_OLEDB_SET_OPTIONS = (
    "SET ARITHABORT OFF;"
    "SET ANSI_NULLS ON;"
    "SET ANSI_PADDING ON;"
    "SET ANSI_WARNINGS ON;"
    "SET CONCAT_NULL_YIELDS_NULL ON;"
    "SET QUOTED_IDENTIFIER ON;"
)


def _base_conn_str(cfg: Config) -> str:
    return (
        f"Driver={{{cfg.odbc_driver}}};"
        f"Server=tcp:{cfg.server},{cfg.port};"
        f"Database={cfg.database};"
        f"Encrypt={cfg.odbc_encrypt};"
        f"TrustServerCertificate={cfg.odbc_trust_server_cert};"
        "Connection Timeout=30;"
    )


def _aad_token_attrs(cfg: Config) -> dict:
    """Acquire an AAD access token and pack it for the ODBC driver."""
    from azure.identity import ClientSecretCredential, DefaultAzureCredential

    if cfg.auth_mode == "aad-service-principal":
        credential = ClientSecretCredential(
            tenant_id=cfg.aad_tenant_id,
            client_id=cfg.aad_client_id,
            client_secret=cfg.aad_client_secret,
        )
    else:  # aad-integrated
        credential = DefaultAzureCredential()

    token = credential.get_token(_AAD_SCOPE).token
    token_bytes = token.encode("utf-16-le")
    packed = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return {_SQL_COPT_SS_ACCESS_TOKEN: packed}


def connect(cfg: Config) -> pyodbc.Connection:
    """Open a new pyodbc connection according to cfg.auth_mode."""
    conn_str = _base_conn_str(cfg)

    if cfg.auth_mode == "sql":
        conn_str += f"UID={cfg.sql_user};PWD={cfg.sql_password};"
        conn = pyodbc.connect(conn_str)
    elif cfg.auth_mode == "aad-password":
        conn_str += (
            "Authentication=ActiveDirectoryPassword;"
            f"UID={cfg.sql_user};PWD={cfg.sql_password};"
        )
        conn = pyodbc.connect(conn_str)
    else:  # aad-integrated / aad-service-principal -> access token
        conn = pyodbc.connect(conn_str, attrs_before=_aad_token_attrs(cfg))

    if cfg.mimic_oledb_set_options:
        with conn.cursor() as cur:
            cur.execute(_OLEDB_SET_OPTIONS)
        conn.commit()

    return conn
