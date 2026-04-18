use std::collections::HashMap;
use std::env;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{LazyLock, Mutex};

use crate::api::{
    RustAccountTree, RustAccountTreeQuery, RustDiagnosticQuery, RustDocument, RustDocumentSummary,
    RustJournalPage, RustJournalQuery, RustRefreshResult, RustReportQuery, RustReportSnapshot,
    RustWorkspaceSummary,
};
use crate::engine::query;
use crate::engine::semantic::{lower_syntax_tree, SemanticLedger};
use crate::engine::source::{load_workspace_source, WorkspaceSourceSet};
use crate::engine::syntax::{parse_source_set, SyntaxTree};
use crate::ledger;

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static SESSIONS: LazyLock<Mutex<HashMap<i64, WorkspaceSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

const PARSER_BACKEND_ENV: &str = "TALLY_BEAN_PARSER_BACKEND";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ParserBackend {
    Legacy,
    SyntaxFoundation,
}

impl ParserBackend {
    fn from_environment() -> Self {
        match env::var(PARSER_BACKEND_ENV).ok().as_deref() {
            Some("syntax") | Some("syntax-foundation") => Self::SyntaxFoundation,
            _ => Self::Legacy,
        }
    }

    #[cfg(test)]
    fn name(self) -> &'static str {
        match self {
            Self::Legacy => "legacy",
            Self::SyntaxFoundation => "syntax-foundation",
        }
    }
}

#[derive(Clone, Debug)]
struct WorkspaceSession {
    root_path: String,
    entry_file_path: String,
    #[allow(dead_code)]
    parser_backend: ParserBackend,
    snapshot: crate::api::RustLedgerSnapshot,
    #[allow(dead_code)]
    source_set: WorkspaceSourceSet,
    #[allow(dead_code)]
    syntax_tree: Option<SyntaxTree>,
    #[allow(dead_code)]
    semantic_ledger: Option<SemanticLedger>,
}

impl WorkspaceSession {
    fn load(root_path: String, entry_file_path: String) -> Self {
        Self::load_with_backend(root_path, entry_file_path, ParserBackend::from_environment())
    }

    fn load_with_backend(
        root_path: String,
        entry_file_path: String,
        parser_backend: ParserBackend,
    ) -> Self {
        let source_set = load_workspace_source(&root_path, &entry_file_path);
        let snapshot = ledger::parse_workspace(&root_path, &entry_file_path);
        let syntax_tree = match parser_backend {
            ParserBackend::Legacy => None,
            ParserBackend::SyntaxFoundation => Some(parse_source_set(&source_set)),
        };
        let semantic_ledger = syntax_tree
            .as_ref()
            .map(|syntax_tree| lower_syntax_tree(&source_set, syntax_tree));
        Self {
            root_path,
            entry_file_path,
            parser_backend,
            snapshot,
            source_set,
            syntax_tree,
            semantic_ledger,
        }
    }
}

pub(crate) fn open_workspace(root_path: String, entry_file_path: String) -> i64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let session = WorkspaceSession::load(root_path, entry_file_path);
    SESSIONS.lock().expect("session lock").insert(handle, session);
    handle
}

pub(crate) fn close_workspace(handle: i64) {
    SESSIONS.lock().expect("session lock").remove(&handle);
}

pub(crate) fn refresh_workspace(handle: i64) -> RustRefreshResult {
    let mut sessions = SESSIONS.lock().expect("session lock");
    let session = sessions
        .get_mut(&handle)
        .unwrap_or_else(|| panic!("unknown workspace handle: {handle}"));
    *session = WorkspaceSession::load(session.root_path.clone(), session.entry_file_path.clone());
    RustRefreshResult {
        summary: workspace_summary_result(session).summary,
        diagnostics_count: session.snapshot.diagnostics.len() as i32,
    }
}

#[cfg(test)]
pub(crate) fn open_workspace_with_backend(
    root_path: String,
    entry_file_path: String,
    parser_backend: ParserBackend,
) -> i64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let session = WorkspaceSession::load_with_backend(root_path, entry_file_path, parser_backend);
    SESSIONS.lock().expect("session lock").insert(handle, session);
    handle
}

pub(crate) fn get_workspace_summary(handle: i64) -> RustWorkspaceSummary {
    with_session(handle, |session| workspace_summary_result(session).summary)
}

pub(crate) fn list_diagnostics(
    handle: i64,
    query_request: RustDiagnosticQuery,
) -> Vec<crate::api::RustLedgerDiagnostic> {
    with_session(handle, |session| {
        query::filter_diagnostics(&session.snapshot, &query_request)
    })
}

pub(crate) fn get_journal_page(handle: i64, query_request: RustJournalQuery) -> RustJournalPage {
    with_session(handle, |session| journal_page_result(session, &query_request).page)
}

pub(crate) fn get_account_tree(
    handle: i64,
    query_request: RustAccountTreeQuery,
) -> RustAccountTree {
    with_session(handle, |session| {
        query::build_account_tree(&session.snapshot, &query_request)
    })
}

pub(crate) fn get_report_snapshot(
    handle: i64,
    query_request: RustReportQuery,
) -> RustReportSnapshot {
    with_session(handle, |session| {
        query::build_report_snapshot(&session.snapshot, &query_request)
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

fn with_session<T>(handle: i64, callback: impl FnOnce(&WorkspaceSession) -> T) -> T {
    let sessions = SESSIONS.lock().expect("session lock");
    let session = sessions
        .get(&handle)
        .unwrap_or_else(|| panic!("unknown workspace handle: {handle}"));
    callback(session)
}

fn workspace_summary_result(session: &WorkspaceSession) -> SummaryQueryResult {
    if let Some(semantic_ledger) = &session.semantic_ledger {
        if semantic_ledger.is_fully_supported_for_queries {
            return SummaryQueryResult {
                summary: query::build_workspace_summary_from_semantic(semantic_ledger),
                source: QuerySource::Semantic,
            };
        }
    }

    SummaryQueryResult {
        summary: query::build_workspace_summary(&session.snapshot),
        source: QuerySource::Legacy,
    }
}

fn journal_page_result(
    session: &WorkspaceSession,
    query_request: &RustJournalQuery,
) -> JournalQueryResult {
    if let Some(semantic_ledger) = &session.semantic_ledger {
        if semantic_ledger.is_fully_supported_for_queries {
            return JournalQueryResult {
                page: query::build_journal_page_from_semantic(semantic_ledger, query_request),
                source: QuerySource::Semantic,
            };
        }
    }

    JournalQueryResult {
        page: query::build_journal_page(&session.snapshot, query_request),
        source: QuerySource::Legacy,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum QuerySource {
    Legacy,
    Semantic,
}

impl QuerySource {
    #[cfg(test)]
    fn name(self) -> &'static str {
        match self {
            Self::Legacy => "legacy",
            Self::Semantic => "semantic",
        }
    }
}

struct SummaryQueryResult {
    summary: RustWorkspaceSummary,
    #[cfg_attr(not(test), allow(dead_code))]
    source: QuerySource,
}

struct JournalQueryResult {
    page: RustJournalPage,
    #[cfg_attr(not(test), allow(dead_code))]
    source: QuerySource,
}

#[cfg(test)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SessionDebugSnapshot {
    pub(crate) backend_name: String,
    pub(crate) syntax_document_count: usize,
    pub(crate) syntax_diagnostic_count: usize,
    pub(crate) semantic_available: bool,
    pub(crate) summary_source: String,
    pub(crate) journal_source: String,
}

#[cfg(test)]
pub(crate) fn debug_session_snapshot(handle: i64) -> SessionDebugSnapshot {
    with_session(handle, |session| {
        let summary_result = workspace_summary_result(session);
        let journal_result = journal_page_result(
            session,
            &RustJournalQuery {
                page_size: 50,
                offset: 0,
            },
        );
        SessionDebugSnapshot {
            backend_name: session.parser_backend.name().to_owned(),
            syntax_document_count: session
                .syntax_tree
                .as_ref()
                .map(|tree| tree.cst.documents.len())
                .unwrap_or_default(),
            syntax_diagnostic_count: session
                .syntax_tree
                .as_ref()
                .map(|tree| tree.diagnostics.len())
                .unwrap_or_default(),
            semantic_available: session
                .semantic_ledger
                .as_ref()
                .map(|ledger| ledger.is_fully_supported_for_queries)
                .unwrap_or(false),
            summary_source: summary_result.source.name().to_owned(),
            journal_source: journal_result.source.name().to_owned(),
        }
    })
}
