use crate::engine;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RustTransactionFlag {
    Cleared,
    Pending,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustAmount {
    pub value: f64,
    pub commodity: String,
    pub fraction_digits: i32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustLedgerDiagnostic {
    pub message: String,
    pub location: String,
    pub blocking: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustTrendSummary {
    pub chart_label: String,
    pub income: f64,
    pub expense: f64,
    pub balance: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustLedgerSummary {
    pub ledger_id: String,
    pub ledger_name: String,
    pub operating_currencies: Vec<String>,
    pub loaded_file_count: i32,
    pub open_account_count: i32,
    pub closed_account_count: i32,
    pub net_worth: String,
    pub total_assets: String,
    pub total_liabilities: String,
    pub change_description: String,
    pub week_trend: RustTrendSummary,
    pub month_trend: RustTrendSummary,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RustJournalEntryType {
    Transaction,
    Open,
    Close,
    Price,
    Balance,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustJournalEntry {
    pub date_iso8601: String,
    pub entry_type: RustJournalEntryType,
    pub title: String,
    pub primary_account: String,
    pub secondary_account: Option<String>,
    pub detail: Option<String>,
    pub amount: Option<RustAmount>,
    pub status: Option<String>,
    pub transaction_flag: Option<RustTransactionFlag>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RustJournalQuery {
    pub page_size: i32,
    pub offset: i32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustJournalPage {
    pub total_count: i32,
    pub entries: Vec<RustJournalEntry>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustAccountNode {
    pub name: String,
    pub subtitle: String,
    pub balance: String,
    pub is_closed: bool,
    pub is_postable: bool,
    pub children: Vec<RustAccountNode>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RustAccountTreeQuery {
    pub include_closed_accounts: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustAccountTree {
    pub nodes: Vec<RustAccountNode>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RustReportQuery {}

#[derive(Clone, Debug, PartialEq)]
pub struct RustReportResult {
    pub key: String,
    pub lines: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustReportSnapshot {
    pub results: Vec<RustReportResult>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RustDiagnosticQuery {
    pub include_blocking: bool,
    pub include_non_blocking: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustDocumentSummary {
    pub document_id: String,
    pub file_name: String,
    pub relative_path: String,
    pub size_bytes: i32,
    pub is_entry: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustDocument {
    pub document_id: String,
    pub file_name: String,
    pub relative_path: String,
    pub content: String,
    pub size_bytes: i32,
    pub is_entry: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RustRefreshResult {
    pub summary: RustLedgerSummary,
    pub diagnostics_count: i32,
}

pub fn open_ledger_session(root_path: String, entry_file_path: String) -> i64 {
    engine::session::open_ledger_session(root_path, entry_file_path)
}

pub fn close_ledger_session(handle: i64) {
    engine::session::close_ledger_session(handle)
}

pub fn refresh_ledger_session(handle: i64) -> RustRefreshResult {
    engine::session::refresh_ledger_session(handle)
}

pub fn get_ledger_summary(handle: i64) -> RustLedgerSummary {
    engine::session::get_ledger_summary(handle)
}

pub fn list_diagnostics(handle: i64, query: RustDiagnosticQuery) -> Vec<RustLedgerDiagnostic> {
    engine::session::list_diagnostics(handle, query)
}

pub fn get_journal_page(handle: i64, query: RustJournalQuery) -> RustJournalPage {
    engine::session::get_journal_page(handle, query)
}

pub fn get_account_tree(handle: i64, query: RustAccountTreeQuery) -> RustAccountTree {
    engine::session::get_account_tree(handle, query)
}

pub fn get_report_snapshot(handle: i64, query: RustReportQuery) -> RustReportSnapshot {
    engine::session::get_report_snapshot(handle, query)
}

pub fn list_documents(handle: i64) -> Vec<RustDocumentSummary> {
    engine::session::list_documents(handle)
}

pub fn get_document(handle: i64, document_id: String) -> RustDocument {
    engine::session::get_document(handle, document_id)
}
