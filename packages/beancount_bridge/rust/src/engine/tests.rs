use std::fs;

use tempfile::tempdir;

use crate::api::{
    close_ledger_session, get_account_tree, get_document, get_journal_page, get_ledger_summary,
    get_report_snapshot, list_diagnostics, list_documents, open_ledger_session, parse_ledger,
    refresh_ledger_session, RustAccountTreeQuery, RustDiagnosticQuery, RustJournalQuery,
    RustLedgerDirectiveKind, RustReportQuery,
};
use crate::engine::ast::AstDirective;
use crate::engine::cst::CstItem;
use crate::engine::index::build_query_index;
use crate::engine::query::{build_journal_page_from_semantic, build_ledger_summary_from_semantic};
use crate::engine::semantic::lower_syntax_tree;
use crate::engine::session::debug_session_snapshot;
use crate::engine::source::load_ledger_source;
use crate::engine::syntax::parse_source_set;

#[test]
fn source_loader_follows_include_graph_and_skips_unreferenced_documents() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "include \"journal.beancount\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("journal.beancount"),
        concat!(
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("scratch.beancount"),
        "2026-04-09 open Assets:Ignored CNY\n",
    )
    .unwrap();

    let documents = load_ledger_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    )
    .documents;

    let relative_paths = documents
        .iter()
        .map(|document| document.relative_path.as_str())
        .collect::<Vec<_>>();
    assert_eq!(relative_paths, vec!["main.beancount", "journal.beancount"]);
}

#[test]
fn syntax_pipeline_builds_cst_and_ast_for_include_open_and_transaction_inputs() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "include \"journal.beancount\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("journal.beancount"),
        concat!(
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();

    let source_set = load_ledger_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    );
    let syntax = parse_source_set(&source_set);

    assert!(syntax.diagnostics.is_empty(), "{:?}", syntax.diagnostics);
    assert_eq!(syntax.cst.documents.len(), 2);
    assert_eq!(syntax.ast.documents.len(), 2);

    let main_document = &syntax.cst.documents[0];
    assert!(matches!(main_document.items[0], CstItem::Include(_)));
    assert!(matches!(main_document.items[1], CstItem::Open(_)));

    let ast_directives = syntax
        .ast
        .documents
        .iter()
        .flat_map(|document| document.directives.iter())
        .collect::<Vec<_>>();
    assert!(matches!(ast_directives[0], AstDirective::Include(_)));
    assert!(matches!(ast_directives[1], AstDirective::Open(_)));
    assert!(matches!(ast_directives[3], AstDirective::Transaction(_)));
}

#[test]
fn syntax_pipeline_marks_unsupported_dated_directives_and_excludes_them_from_ast() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 price USD 7.24 CNY\n",
            "2026-04-02 balance Assets:Cash 10 CNY\n",
            "2026-04-03 close Assets:Cash\n",
            "2026-04-04 note Assets:Cash \"unsupported\"\n",
        ),
    )
    .unwrap();

    let source_set = load_ledger_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    );
    let syntax = parse_source_set(&source_set);

    assert!(syntax
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.message.contains("暂不支持 note 指令") && !diagnostic.blocking));
    assert_eq!(syntax.ast.documents.len(), 1);
    assert_eq!(syntax.ast.documents[0].directives.len(), 4);
}

#[test]
fn semantic_lowering_builds_summary_and_journal_from_semantic_index() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "option \"title\" \"语法账本\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
            "2026-04-01 price USD 7.24 CNY\n",
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
            "2026-04-03 balance Assets:Cash 1000 CNY\n",
            "2026-04-04 close Assets:Cash\n",
        ),
    )
    .unwrap();

    let source_set = load_ledger_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    );
    let syntax = parse_source_set(&source_set);
    let semantic = lower_syntax_tree(&source_set, &syntax);
    let index = build_query_index(&semantic);
    let summary = build_ledger_summary_from_semantic(&semantic, &index);
    let journal = build_journal_page_from_semantic(
        &semantic,
        &index,
        &RustJournalQuery {
            page_size: 50,
            offset: 0,
        },
    );

    assert!(
        semantic.diagnostics.is_empty(),
        "{:?}",
        semantic.diagnostics
    );
    assert_eq!(summary.ledger_id, "ledger");
    assert_eq!(summary.ledger_name, "语法账本");
    assert_eq!(summary.loaded_file_count, 1);
    assert_eq!(summary.open_account_count, 2);
    assert_eq!(summary.closed_account_count, 1);
    assert_eq!(summary.net_worth, "CNY 1,000");
    assert_eq!(journal.total_count, 6);
    assert_eq!(journal.entries.first().unwrap().title, "Assets:Cash");
    assert_eq!(journal.entries[1].title, "Assets:Cash");
    assert_eq!(journal.entries[2].title, "Salary");
}

#[test]
fn semantic_lowering_uses_title_option_with_utf8_bom_prefix() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "\u{feff}option \"title\" \"BOM 语法账本\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
        ),
    )
    .unwrap();

    let source_set = load_ledger_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    );
    let syntax = parse_source_set(&source_set);
    let semantic = lower_syntax_tree(&source_set, &syntax);
    let index = build_query_index(&semantic);
    let summary = build_ledger_summary_from_semantic(&semantic, &index);

    assert_eq!(summary.ledger_name, "BOM 语法账本");
}

#[test]
fn parse_ledger_returns_engine_backed_compat_snapshot() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "include \"journal.beancount\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("journal.beancount"),
        concat!(
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();

    let snapshot = parse_ledger(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert_eq!(snapshot.loaded_file_count, 2);
    assert!(snapshot.diagnostics.is_empty(), "{:?}", snapshot.diagnostics);
    assert_eq!(snapshot.directives[0].source_location, "main.beancount:2");
    let transaction = snapshot
        .directives
        .iter()
        .find(|directive| directive.kind == RustLedgerDirectiveKind::Transaction)
        .unwrap();
    assert_eq!(transaction.source_location, "journal.beancount:1");
    assert_eq!(
        transaction.postings[1].amount.as_ref().unwrap().value,
        -1000.0
    );
}

#[test]
fn engine_session_debug_snapshot_reports_engine_only_state() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "include \"journal.beancount\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("journal.beancount"),
        concat!(
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();

    let handle = open_ledger_session(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    let debug = debug_session_snapshot(handle);
    close_ledger_session(handle);

    assert_eq!(debug.document_count, 2);
    assert_eq!(debug.syntax_document_count, 2);
    assert_eq!(debug.syntax_diagnostic_count, 0);
    assert_eq!(debug.semantic_directive_count, 3);
    assert_eq!(debug.semantic_diagnostic_count, 0);
    assert_eq!(debug.indexed_account_count, 2);
}

#[test]
fn engine_session_exposes_summary_queries_and_documents() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(root.join("transactions")).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "include \"transactions/journal.beancount\"\n",
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
        ),
    )
    .unwrap();
    fs::write(
        root.join("transactions/journal.beancount"),
        concat!(
            "2026-04-02 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();

    let handle = open_ledger_session(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    let summary = get_ledger_summary(handle);
    assert_eq!(summary.ledger_id, "ledger");
    assert_eq!(summary.loaded_file_count, 2);
    assert_eq!(summary.open_account_count, 2);
    assert_eq!(summary.closed_account_count, 0);
    assert_eq!(summary.net_worth, "CNY 1,000");

    let diagnostics = list_diagnostics(
        handle,
        RustDiagnosticQuery {
            include_blocking: true,
            include_non_blocking: true,
        },
    );
    assert!(diagnostics.is_empty());

    let journal = get_journal_page(
        handle,
        RustJournalQuery {
            page_size: 50,
            offset: 0,
        },
    );
    assert_eq!(journal.total_count, 3);
    assert_eq!(journal.entries.first().unwrap().title, "Salary");

    let account_tree = get_account_tree(
        handle,
        RustAccountTreeQuery {
            include_closed_accounts: true,
        },
    );
    assert_eq!(account_tree.nodes.len(), 2);
    assert_eq!(account_tree.nodes.first().unwrap().name, "Assets");

    let reports = get_report_snapshot(handle, RustReportQuery {});
    assert_eq!(reports.results.len(), 1);
    assert_eq!(reports.results.first().unwrap().key, "income_expense");

    let documents = list_documents(handle);
    assert_eq!(documents.len(), 2);
    assert_eq!(documents.first().unwrap().relative_path, "main.beancount");
    assert!(documents.first().unwrap().is_entry);

    let document = get_document(handle, documents.first().unwrap().document_id.clone());
    assert_eq!(document.relative_path, "main.beancount");
    assert!(document.content.contains("open Assets:Cash CNY"));

    close_ledger_session(handle);
}

#[test]
fn engine_session_reports_account_lifecycle_diagnostics_without_fallback() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-02 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-01 * \"Before open\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Income:Salary -100 CNY\n",
            "2026-04-03 close Assets:Cash\n",
            "2026-04-04 * \"After close\"\n",
            "  Assets:Cash -100 CNY\n",
            "  Equity:Opening-Balances 100 CNY\n",
        ),
    )
    .unwrap();

    let handle = open_ledger_session(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    let summary = get_ledger_summary(handle);
    let diagnostics = list_diagnostics(
        handle,
        RustDiagnosticQuery {
            include_blocking: true,
            include_non_blocking: true,
        },
    );
    close_ledger_session(handle);

    assert_eq!(summary.ledger_id, "ledger");
    assert!(diagnostics
        .iter()
        .all(|diagnostic| diagnostic.location.starts_with("main.beancount:")));
    assert!(diagnostics
        .iter()
        .any(|diagnostic| diagnostic.message.contains("账户在开户前被引用: Assets:Cash")));
    assert!(diagnostics
        .iter()
        .any(|diagnostic| diagnostic.message.contains("未知账户: Income:Salary")));
    assert!(diagnostics
        .iter()
        .any(|diagnostic| diagnostic.message.contains("账户在关闭后被引用: Assets:Cash")));
}

#[test]
fn refresh_ledger_session_reloads_engine_state() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-02 * \"Seed\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Equity:Opening-Balances\n",
        ),
    )
    .unwrap();

    let handle = open_ledger_session(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );
    let initial = get_ledger_summary(handle);
    assert_eq!(initial.open_account_count, 2);
    assert_eq!(initial.closed_account_count, 0);

    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-02 * \"Seed\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Equity:Opening-Balances\n",
            "2026-04-03 close Assets:Cash\n",
        ),
    )
    .unwrap();

    let refreshed = refresh_ledger_session(handle);
    assert_eq!(refreshed.summary.closed_account_count, 1);
    assert_eq!(refreshed.diagnostics_count, 0);

    close_ledger_session(handle);
}
