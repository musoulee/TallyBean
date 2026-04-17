use crate::parser;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RustLedgerDirectiveKind {
    Transaction,
    Open,
    Close,
    Price,
    Balance,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RustTransactionFlag {
    Cleared,
    Pending,
}

#[derive(Clone, Debug)]
pub struct RustAmount {
    pub value: f64,
    pub commodity: String,
    pub fraction_digits: i32,
}

#[derive(Clone, Debug)]
pub struct RustPosting {
    pub account: String,
    pub amount: Option<RustAmount>,
}

#[derive(Clone, Debug)]
pub struct RustLedgerDiagnostic {
    pub message: String,
    pub location: String,
    pub blocking: bool,
}

#[derive(Clone, Debug)]
pub struct RustLedgerDirective {
    pub kind: RustLedgerDirectiveKind,
    pub date_iso8601: String,
    pub source_location: String,
    pub account: Option<String>,
    pub title: Option<String>,
    pub base_commodity: Option<String>,
    pub quote_commodity: Option<String>,
    pub amount: Option<RustAmount>,
    pub transaction_flag: Option<RustTransactionFlag>,
    pub postings: Vec<RustPosting>,
}

#[derive(Clone, Debug)]
pub struct RustLedgerSnapshot {
    pub workspace_id: String,
    pub workspace_name: String,
    pub loaded_file_count: i32,
    pub directives: Vec<RustLedgerDirective>,
    pub diagnostics: Vec<RustLedgerDiagnostic>,
}

pub fn parse_workspace(root_path: String, entry_file_path: String) -> RustLedgerSnapshot {
    parser::parse_workspace(&root_path, &entry_file_path)
}
