use std::fs;

use tempfile::tempdir;

use crate::api::RustJournalQuery;
use crate::engine::ast::AstDirective;
use crate::engine::cst::CstItem;
use crate::engine::query::{
    build_journal_page_from_semantic, build_workspace_summary_from_semantic,
};
use crate::engine::semantic::lower_syntax_tree;
use crate::engine::session::{
    close_workspace, debug_session_snapshot, get_journal_page, get_workspace_summary,
    open_workspace_with_backend, ParserBackend,
};
use crate::engine::source::load_workspace_source;
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

    let documents = load_workspace_source(
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

    let source_set = load_workspace_source(
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

    let source_set = load_workspace_source(
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
fn semantic_lowering_builds_summary_and_journal_from_supported_syntax_tree() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
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

    let source_set = load_workspace_source(
        &root.display().to_string(),
        &root.join("main.beancount").display().to_string(),
    );
    let syntax = parse_source_set(&source_set);
    let semantic = lower_syntax_tree(&source_set, &syntax);
    let summary = build_workspace_summary_from_semantic(&semantic);
    let journal = build_journal_page_from_semantic(
        &semantic,
        &RustJournalQuery {
            page_size: 50,
            offset: 0,
        },
    );

    assert!(semantic.is_fully_supported_for_queries);
    assert!(semantic.diagnostics.is_empty(), "{:?}", semantic.diagnostics);
    assert_eq!(summary.workspace_id, "ledger");
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
fn workspace_session_can_enable_syntax_foundation_backend_without_breaking_summary_queries() {
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

    let handle = open_workspace_with_backend(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
        ParserBackend::SyntaxFoundation,
    );

    let debug = debug_session_snapshot(handle);
    let summary = get_workspace_summary(handle);
    close_workspace(handle);

    assert_eq!(debug.backend_name, "syntax-foundation");
    assert_eq!(debug.syntax_document_count, 2);
    assert_eq!(summary.workspace_id, "ledger");
    assert_eq!(summary.loaded_file_count, 2);
}

#[test]
fn workspace_session_falls_back_to_legacy_queries_when_semantic_coverage_is_incomplete() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Income:Salary CNY\n",
            "2026-04-02 note Assets:Cash \"unsupported\"\n",
            "2026-04-03 * \"Salary\"\n",
            "  Assets:Cash 1000 CNY\n",
            "  Income:Salary\n",
        ),
    )
    .unwrap();

    let handle = open_workspace_with_backend(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
        ParserBackend::SyntaxFoundation,
    );

    let debug = debug_session_snapshot(handle);
    let summary = get_workspace_summary(handle);
    let journal = get_journal_page(
        handle,
        RustJournalQuery {
            page_size: 50,
            offset: 0,
        },
    );
    close_workspace(handle);

    assert!(!debug.semantic_available);
    assert_eq!(debug.summary_source, "legacy");
    assert_eq!(debug.journal_source, "legacy");
    assert_eq!(summary.net_worth, "CNY 1,000");
    assert_eq!(journal.entries.first().unwrap().title, "Salary");
}
