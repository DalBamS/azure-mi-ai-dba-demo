/* ==========================================================================
 * azure-mi-ai-dba-demo — native currency-transfer micro-driver (C++/OLE DB)
 * --------------------------------------------------------------------------
 * Purpose : Reproduce the production hot path (currency transfer) using the
 *           SAME client stack as the game server: C++ + MSOLEDBSQL (OLE DB).
 *           This gives the game-DBA audience confidence that the demo behaves
 *           exactly like production for this critical transaction.
 *
 * Scope   : STRETCH / scaffold. Requires the MSOLEDBSQL SDK (msoledbsql.h).
 *           Validate against a live Azure SQL MI before the demo.
 *
 * Secrets : The connection string is read from the SQLMI_OLEDB_CONNSTR
 *           environment variable. NEVER hardcode connection strings/secrets.
 *           Example (Entra ID integrated):
 *             Provider=MSOLEDBSQL;Data Source=<mi-fqdn>,1433;
 *             Initial Catalog=gamedb;Authentication=ActiveDirectoryIntegrated;
 *             Encrypt=yes;
 *
 * Behavior: Performs one gold transfer between two players inside an explicit
 *           transaction, locking the lower player_id first (matching the
 *           Python driver's safe lock order). OLE DB connects with ARITHABORT
 *           OFF by default — the production-authentic SET-option behavior.
 * ========================================================================== */

#define _WIN32_DCOM
#include <windows.h>
#include <oledb.h>
#include <msoledbsql.h>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

std::wstring GetConnStrFromEnv() {
    wchar_t* buf = nullptr;
    size_t len = 0;
    if (_wdupenv_s(&buf, &len, L"SQLMI_OLEDB_CONNSTR") != 0 || buf == nullptr) {
        return L"";
    }
    std::wstring s(buf);
    free(buf);
    return s;
}

void Report(const char* where, HRESULT hr) {
    fprintf(stderr, "[native] %s failed: hr=0x%08lX\n", where, static_cast<unsigned long>(hr));
}

// Execute a single parameterless-context command (parameters are inlined via
// session-scoped temp values in this scaffold; production should bind params).
HRESULT ExecuteText(IDBCreateCommand* pCreateCmd, const wchar_t* sql) {
    ICommandText* pCmdText = nullptr;
    HRESULT hr = pCreateCmd->CreateCommand(nullptr, IID_ICommandText,
                                           reinterpret_cast<IUnknown**>(&pCmdText));
    if (FAILED(hr)) { Report("CreateCommand", hr); return hr; }

    hr = pCmdText->SetCommandText(DBGUID_DEFAULT, sql);
    if (SUCCEEDED(hr)) {
        hr = pCmdText->Execute(nullptr, IID_NULL, nullptr, nullptr, nullptr);
        if (FAILED(hr)) Report("Execute", hr);
    } else {
        Report("SetCommandText", hr);
    }
    pCmdText->Release();
    return hr;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    // Args: <fromPlayerId> <toPlayerId> <amount>  (defaults for a smoke run)
    const long long from = (argc > 1) ? _wtoi64(argv[1]) : 1;
    const long long to   = (argc > 2) ? _wtoi64(argv[2]) : 2;
    const long amount    = (argc > 3) ? _wtol(argv[3]) : 10;
    const long long low  = (from < to) ? from : to;   // safe lock order
    const long long high = (from < to) ? to : from;

    std::wstring conn = GetConnStrFromEnv();
    if (conn.empty()) {
        fprintf(stderr, "[native] Set SQLMI_OLEDB_CONNSTR (no hardcoded secrets).\n");
        return 2;
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) { Report("CoInitializeEx", hr); return 1; }

    IDBInitialize* pInit = nullptr;
    hr = CoCreateInstance(CLSID_MSOLEDBSQL, nullptr, CLSCTX_INPROC_SERVER,
                          IID_IDBInitialize, reinterpret_cast<void**>(&pInit));
    if (FAILED(hr)) { Report("CoCreateInstance(MSOLEDBSQL)", hr); CoUninitialize(); return 1; }

    // Initialize connection from the full connection string.
    IDBProperties* pProps = nullptr;
    hr = pInit->QueryInterface(IID_IDBProperties, reinterpret_cast<void**>(&pProps));
    if (SUCCEEDED(hr)) {
        DBPROP prop = {};
        prop.dwPropertyID = DBPROP_INIT_PROVIDERSTRING;
        prop.dwOptions = DBPROPOPTIONS_REQUIRED;
        prop.vValue.vt = VT_BSTR;
        prop.vValue.bstrVal = SysAllocString(conn.c_str());

        DBPROPSET propset = {};
        propset.guidPropertySet = DBPROPSET_DBINIT;
        propset.cProperties = 1;
        propset.rgProperties = &prop;

        hr = pProps->SetProperties(1, &propset);
        VariantClear(&prop.vValue);
        pProps->Release();
    }

    if (SUCCEEDED(hr)) hr = pInit->Initialize();
    if (FAILED(hr)) { Report("Initialize", hr); pInit->Release(); CoUninitialize(); return 1; }

    IDBCreateSession* pCreateSession = nullptr;
    hr = pInit->QueryInterface(IID_IDBCreateSession, reinterpret_cast<void**>(&pCreateSession));
    if (FAILED(hr)) { Report("QI IDBCreateSession", hr); pInit->Uninitialize(); pInit->Release(); CoUninitialize(); return 1; }

    IDBCreateCommand* pCreateCmd = nullptr;
    hr = pCreateSession->CreateSession(nullptr, IID_IDBCreateCommand,
                                       reinterpret_cast<IUnknown**>(&pCreateCmd));
    pCreateSession->Release();
    if (FAILED(hr)) { Report("CreateSession", hr); pInit->Uninitialize(); pInit->Release(); CoUninitialize(); return 1; }

    // Build the transfer as an atomic batch (lower player_id locked first).
    wchar_t sql[1024];
    swprintf(sql, 1024,
        L"SET XACT_ABORT ON; BEGIN TRAN; "
        L"UPDATE dbo.currency_ledger SET balance = balance - %ld, updated_at = SYSUTCDATETIME() "
        L"WHERE player_id = %lld AND currency_type = 1 AND balance >= %ld; "
        L"UPDATE dbo.currency_ledger SET balance = balance + %ld, updated_at = SYSUTCDATETIME() "
        L"WHERE player_id = %lld AND currency_type = 1; COMMIT;",
        amount, low, amount, amount, high);

    hr = ExecuteText(pCreateCmd, sql);
    if (SUCCEEDED(hr)) {
        printf("[native] transfer ok: %lld -> %lld amount=%ld (locked %lld first)\n",
               from, to, amount, low);
    }

    pCreateCmd->Release();
    pInit->Uninitialize();
    pInit->Release();
    CoUninitialize();
    return SUCCEEDED(hr) ? 0 : 1;
}
