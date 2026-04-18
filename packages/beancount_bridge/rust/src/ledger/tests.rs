use std::fs;

use tempfile::tempdir;

use crate::api::{
    close_workspace, get_account_tree, get_document, get_journal_page, get_report_snapshot,
    get_workspace_summary, list_diagnostics, list_documents, open_workspace, parse_workspace,
    refresh_workspace, RustAccountTreeQuery, RustDiagnosticQuery, RustJournalQuery,
    RustLedgerDirectiveKind, RustReportQuery,
};

#[test]
fn parses_includes_and_autobalances_transactions() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        "include \"journal.beancount\"\n2026-04-01 open Assets:Cash CNY\n2026-04-01 open Income:Salary CNY\n",
    )
    .unwrap();
    fs::write(
        root.join("journal.beancount"),
        "2026-04-02 * \"Salary\"\n  Assets:Cash  1000 CNY\n  Income:Salary\n",
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert_eq!(snapshot.workspace_id, "ledger");
    assert_eq!(snapshot.loaded_file_count, 2);
    assert!(snapshot.diagnostics.is_empty());
    assert!(snapshot
        .directives
        .iter()
        .any(|directive| directive.kind == RustLedgerDirectiveKind::Transaction));
    let transaction = snapshot
        .directives
        .iter()
        .find(|directive| directive.kind == RustLedgerDirectiveKind::Transaction)
        .unwrap();
    assert_eq!(transaction.postings.len(), 2);
    assert_eq!(
        transaction.postings[1].amount.as_ref().unwrap().value,
        -1000.0
    );
}

#[test]
fn reports_non_blocking_warnings_for_unsupported_dated_directives() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        "2026-04-01 open Assets:Cash CNY\n2026-04-01 open Equity:Opening-Balances CNY\n2026-04-02 note Assets:Cash \"现金账户备注\"\n2026-04-03 * \"初始化\"\n  Assets:Cash 100 CNY\n  Equity:Opening-Balances\n",
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message.contains("暂不支持 note 指令") && !issue.blocking));
}

#[test]
fn rejects_includes_outside_the_workspace_root() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        "include \"../outside.beancount\"\n2026-04-01 open Assets:Cash CNY\n",
    )
    .unwrap();
    fs::write(sandbox.path().join("outside.beancount"), "").unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message == "include 超出工作区根目录限制" && issue.blocking));
}

#[test]
fn reports_blocking_errors_for_accounts_used_before_open() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        "2026-04-02 open Assets:Cash CNY\n2026-04-01 * \"Oops\"\n  Assets:Cash 100 CNY\n  Income:Salary -100 CNY\n",
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message.contains("账户在开户前被引用: Assets:Cash")));
    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message.contains("未知账户: Income:Salary")));
}

#[test]
fn reports_blocking_errors_for_missing_include_files() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        "include \"missing.beancount\"\n2026-04-01 open Assets:Cash CNY\n",
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message == "include 文件不存在" && issue.blocking));
}

#[test]
fn reports_blocking_errors_for_include_cycles() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(root.join("main.beancount"), "include \"a.beancount\"\n").unwrap();
    fs::write(root.join("a.beancount"), "include \"main.beancount\"\n").unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(snapshot
        .diagnostics
        .iter()
        .any(|issue| issue.message == "检测到 include 循环" && issue.blocking));
}

#[test]
fn reports_blocking_errors_for_unbalanced_transactions() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-02 * \"Oops\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Equity:Opening-Balances -90 CNY\n",
        ),
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(
        snapshot
            .diagnostics
            .iter()
            .any(|issue| issue.message == "Transaction 不平衡" && issue.blocking),
        "{:?}",
        snapshot
            .diagnostics
            .iter()
            .map(|item| item.message.clone())
            .collect::<Vec<_>>()
    );
}

#[test]
fn reports_blocking_errors_for_accounts_used_after_close() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-02 close Assets:Cash\n",
            "2026-04-03 * \"After close\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Equity:Opening-Balances -100 CNY\n",
        ),
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(
        snapshot
            .diagnostics
            .iter()
            .any(|issue| issue.message.contains("账户在关闭后被引用: Assets:Cash")),
        "{:?}",
        snapshot
            .diagnostics
            .iter()
            .map(|item| item.message.clone())
            .collect::<Vec<_>>()
    );
}

#[test]
fn parses_open_close_price_balance_without_blocking_diagnostics() {
    let sandbox = tempdir().unwrap();
    let root = sandbox.path().join("ledger");
    fs::create_dir_all(&root).unwrap();
    fs::write(
        root.join("main.beancount"),
        concat!(
            "2026-04-01 open Assets:Cash CNY\n",
            "2026-04-01 open Equity:Opening-Balances CNY\n",
            "2026-04-01 price USD 7.24 CNY\n",
            "2026-04-02 * \"Seed\"\n",
            "  Assets:Cash 100 CNY\n",
            "  Equity:Opening-Balances -100 CNY\n",
            "2026-04-03 balance Assets:Cash 100 CNY\n",
            "2026-04-04 close Assets:Cash\n",
        ),
    )
    .unwrap();

    let snapshot = parse_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    assert!(
        !snapshot.diagnostics.iter().any(|issue| issue.blocking),
        "{:?}",
        snapshot
            .diagnostics
            .iter()
            .map(|item| item.message.clone())
            .collect::<Vec<_>>()
    );
    assert!(snapshot
        .directives
        .iter()
        .any(|item| item.kind == RustLedgerDirectiveKind::Open));
    assert!(snapshot
        .directives
        .iter()
        .any(|item| item.kind == RustLedgerDirectiveKind::Close));
    assert!(snapshot
        .directives
        .iter()
        .any(|item| item.kind == RustLedgerDirectiveKind::Price));
    assert!(snapshot
        .directives
        .iter()
        .any(|item| item.kind == RustLedgerDirectiveKind::Balance));
}

#[test]
fn workspace_sessions_expose_summary_queries_and_documents() {
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

    let handle = open_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );

    let summary = get_workspace_summary(handle);
    assert_eq!(summary.workspace_id, "ledger");
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

    close_workspace(handle);
}

#[test]
fn refresh_workspace_reloads_session_state() {
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

    let handle = open_workspace(
        root.display().to_string(),
        root.join("main.beancount").display().to_string(),
    );
    let initial = get_workspace_summary(handle);
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

    let refreshed = refresh_workspace(handle);
    assert_eq!(refreshed.summary.closed_account_count, 1);
    assert_eq!(refreshed.diagnostics_count, 0);

    close_workspace(handle);
}
