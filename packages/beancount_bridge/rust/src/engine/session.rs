use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{LazyLock, Mutex};

use crate::api::{
    RustAccountTree, RustAccountTreeQuery, RustDiagnosticQuery, RustDocument, RustDocumentSummary,
    RustJournalPage, RustJournalQuery, RustLedgerSummary, RustRefreshResult, RustReportQuery,
    RustReportSnapshot,
};
use crate::engine::index::{build_query_index, QueryIndex};
use crate::engine::query;
use crate::engine::semantic::{lower_syntax_tree, SemanticLedger};
use crate::engine::source::{load_ledger_source, LedgerSourceSet};
use crate::engine::syntax::{parse_source_set, SyntaxTree};

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static SESSIONS: LazyLock<Mutex<HashMap<i64, LedgerSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Clone, Debug)]
struct LedgerSession {
    root_path: String,
    entry_file_path: String,
    source_set: LedgerSourceSet,
    #[allow(dead_code)]
    syntax_tree: SyntaxTree,
    semantic_ledger: SemanticLedger,
    query_index: QueryIndex,
}

impl LedgerSession {
    fn load(root_path: String, entry_file_path: String) -> Self {
        let source_set = load_ledger_source(&root_path, &entry_file_path);
        let syntax_tree = parse_source_set(&source_set);
        let semantic_ledger = lower_syntax_tree(&source_set, &syntax_tree);
        let query_index = build_query_index(&semantic_ledger);
        Self {
            root_path,
            entry_file_path,
            source_set,
            syntax_tree,
            semantic_ledger,
            query_index,
        }
    }
}

pub(crate) fn open_ledger_session(root_path: String, entry_file_path: String) -> i64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let session = LedgerSession::load(root_path, entry_file_path);
    SESSIONS
        .lock()
        .expect("session lock")
        .insert(handle, session);
    handle
}

pub(crate) fn close_ledger_session(handle: i64) {
    SESSIONS.lock().expect("session lock").remove(&handle);
}

pub(crate) fn refresh_ledger_session(handle: i64) -> RustRefreshResult {
    let mut sessions = SESSIONS.lock().expect("session lock");
    let session = sessions
        .get_mut(&handle)
        .unwrap_or_else(|| panic!("unknown ledger session handle: {handle}"));
    *session = LedgerSession::load(session.root_path.clone(), session.entry_file_path.clone());
    RustRefreshResult {
        summary: query::build_ledger_summary_from_semantic(
            &session.semantic_ledger,
            &session.query_index,
        ),
        diagnostics_count: session.semantic_ledger.diagnostics.len() as i32,
    }
}

pub(crate) fn get_ledger_summary(handle: i64) -> RustLedgerSummary {
    with_session(handle, |session| {
        query::build_ledger_summary_from_semantic(&session.semantic_ledger, &session.query_index)
    })
}

pub(crate) fn list_diagnostics(
    handle: i64,
    query_request: RustDiagnosticQuery,
) -> Vec<crate::api::RustLedgerDiagnostic> {
    with_session(handle, |session| {
        query::filter_diagnostics(&session.semantic_ledger, &query_request)
    })
}

pub(crate) fn get_journal_page(handle: i64, query_request: RustJournalQuery) -> RustJournalPage {
    with_session(handle, |session| {
        query::build_journal_page_from_semantic(
            &session.semantic_ledger,
            &session.query_index,
            &query_request,
        )
    })
}

pub(crate) fn get_account_tree(
    handle: i64,
    query_request: RustAccountTreeQuery,
) -> RustAccountTree {
    with_session(handle, |session| {
        query::build_account_tree_from_semantic(&session.query_index, &query_request)
    })
}

pub(crate) fn get_report_snapshot(
    handle: i64,
    query_request: RustReportQuery,
) -> RustReportSnapshot {
    with_session(handle, |session| {
        query::build_report_snapshot_from_semantic(
            &session.semantic_ledger,
            &session.query_index,
            &query_request,
        )
    })
}

pub(crate) fn list_documents(handle: i64) -> Vec<RustDocumentSummary> {
    with_session(handle, |session| {
        session
            .source_set
            .documents
            .iter()
            .map(|document| RustDocumentSummary {
                document_id: document.document_id.clone(),
                file_name: document.file_name.clone(),
                relative_path: document.relative_path.clone(),
                size_bytes: document.size_bytes,
                is_entry: document.is_entry,
            })
            .collect()
    })
}

pub(crate) fn get_document(handle: i64, document_id: String) -> RustDocument {
    with_session(handle, |session| {
        let document = session
            .source_set
            .documents
            .iter()
            .find(|document| document.document_id == document_id)
            .unwrap_or_else(|| panic!("unknown document id: {document_id}"));
        RustDocument {
            document_id: document.document_id.clone(),
            file_name: document.file_name.clone(),
            relative_path: document.relative_path.clone(),
            content: document.content.clone(),
            size_bytes: document.size_bytes,
            is_entry: document.is_entry,
        }
    })
}

fn with_session<T>(handle: i64, callback: impl FnOnce(&LedgerSession) -> T) -> T {
    let sessions = SESSIONS.lock().expect("session lock");
    let session = sessions
        .get(&handle)
        .unwrap_or_else(|| panic!("unknown ledger session handle: {handle}"));
    callback(session)
}

#[cfg(test)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SessionDebugSnapshot {
    pub(crate) document_count: usize,
    pub(crate) syntax_document_count: usize,
    pub(crate) syntax_diagnostic_count: usize,
    pub(crate) semantic_directive_count: usize,
    pub(crate) semantic_diagnostic_count: usize,
    pub(crate) indexed_account_count: usize,
}

#[cfg(test)]
pub(crate) fn debug_session_snapshot(handle: i64) -> SessionDebugSnapshot {
    with_session(handle, |session| SessionDebugSnapshot {
        document_count: session.source_set.documents.len(),
        syntax_document_count: session.syntax_tree.cst.documents.len(),
        syntax_diagnostic_count: session.syntax_tree.diagnostics.len(),
        semantic_directive_count: session.semantic_ledger.directives.len(),
        semantic_diagnostic_count: session.semantic_ledger.diagnostics.len(),
        indexed_account_count: session.query_index.account_lifecycles.len(),
    })
}
