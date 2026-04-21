use std::collections::{BTreeMap, HashMap};

use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use time::{Date, Duration, Month};

use crate::api::{
    RustAccountNode, RustAccountTree, RustAccountTreeQuery, RustAmount, RustDiagnosticQuery,
    RustJournalEntry, RustJournalEntryType, RustJournalPage, RustJournalQuery,
    RustLedgerDiagnostic, RustLedgerSummary, RustReportQuery, RustReportResult,
    RustReportSnapshot, RustTrendSummary,
};
use crate::engine::index::QueryIndex;
use crate::engine::semantic::{SemanticDirective, SemanticLedger, SemanticPosting};

pub(crate) fn build_ledger_summary_from_semantic(
    semantic_ledger: &SemanticLedger,
    query_index: &QueryIndex,
) -> RustLedgerSummary {
    let reference_date = query_index
        .latest_reference_date
        .unwrap_or_else(today_fallback);
    let asset_buckets = aggregate_account_type("Assets", &query_index.account_balances);
    let liability_buckets = aggregate_account_type("Liabilities", &query_index.account_balances);
    let mut net_worth_buckets = BTreeMap::<String, Decimal>::new();

    for (commodity, value) in &asset_buckets {
        *net_worth_buckets.entry(commodity.clone()).or_default() += *value;
    }
    for (commodity, value) in &liability_buckets {
        *net_worth_buckets.entry(commodity.clone()).or_default() -= value.abs();
    }

    let month_from = Date::from_calendar_date(reference_date.year(), reference_date.month(), 1)
        .expect("valid month start");
    let month_to = next_month_start(reference_date);
    let week_start =
        reference_date - Duration::days(reference_date.weekday().number_days_from_monday().into());
    let week_to = week_start + Duration::days(7);

    let month_trend = build_trend_summary("本月收支趋势", month_from, month_to, semantic_ledger);
    let week_trend = build_trend_summary("本周收支趋势", week_start, week_to, semantic_ledger);
    let previous_month_start = previous_month_start(reference_date);
    let previous_month_trend = build_trend_summary(
        "上月收支趋势",
        previous_month_start,
        month_from,
        semantic_ledger,
    );

    let change_description = dominant_commodity(&net_worth_buckets, &BTreeMap::new())
        .map(|commodity| {
            format!(
                "较上月 {}",
                signed_amount_text(
                    decimal_from_f64(month_trend.balance)
                        - decimal_from_f64(previous_month_trend.balance),
                    &commodity,
                )
            )
        })
        .unwrap_or_else(|| "多币种账本".to_owned());

    RustLedgerSummary {
        ledger_id: semantic_ledger.ledger_id.clone(),
        ledger_name: semantic_ledger.ledger_name.clone(),
        loaded_file_count: semantic_ledger.loaded_file_count,
        open_account_count: query_index.open_account_count(),
        closed_account_count: query_index.closed_account_count(),
        net_worth: format_balance_summary(&net_worth_buckets, false),
        total_assets: format_balance_summary(&asset_buckets, false),
        total_liabilities: format_balance_summary(&liability_buckets, true),
        change_description,
        week_trend,
        month_trend,
    }
}

pub(crate) fn build_journal_page_from_semantic(
    semantic_ledger: &SemanticLedger,
    query_index: &QueryIndex,
    query: &RustJournalQuery,
) -> RustJournalPage {
    let total_count = query_index.journal_order.len() as i32;
    let offset = query.offset.max(0) as usize;
    let page_size = query.page_size.max(0) as usize;
    let entries = if page_size == 0 || offset >= query_index.journal_order.len() {
        Vec::new()
    } else {
        query_index
            .journal_order
            .iter()
            .skip(offset)
            .take(page_size)
            .map(|index| map_journal_entry(&semantic_ledger.directives[*index]))
            .collect()
    };

    RustJournalPage {
        total_count,
        entries,
    }
}

pub(crate) fn build_account_tree_from_semantic(
    query_index: &QueryIndex,
    query: &RustAccountTreeQuery,
) -> RustAccountTree {
    let mut root_nodes = BTreeMap::<String, AccountTreeBuilder>::new();

    for (account, lifecycle) in &query_index.account_lifecycles {
        if !query.include_closed_accounts && lifecycle.close_date.is_some() {
            continue;
        }

        let mut current = None::<&mut AccountTreeBuilder>;
        let mut current_path = String::new();
        for segment in account.split(':') {
            if !current_path.is_empty() {
                current_path.push(':');
            }
            current_path.push_str(segment);

            let next = if let Some(current) = current {
                current
                    .children
                    .entry(segment.to_owned())
                    .or_insert_with(|| {
                        AccountTreeBuilder::new(segment.to_owned(), current_path.clone())
                    })
            } else {
                root_nodes.entry(segment.to_owned()).or_insert_with(|| {
                    AccountTreeBuilder::new(segment.to_owned(), current_path.clone())
                })
            };
            current = Some(next);
        }
    }

    RustAccountTree {
        nodes: root_nodes
            .into_values()
            .map(|builder| build_account_node(&builder, query_index))
            .collect(),
    }
}

pub(crate) fn build_report_snapshot_from_semantic(
    semantic_ledger: &SemanticLedger,
    query_index: &QueryIndex,
    _query: &RustReportQuery,
) -> RustReportSnapshot {
    let summary = build_ledger_summary_from_semantic(semantic_ledger, query_index);
    RustReportSnapshot {
        results: vec![RustReportResult {
            key: "income_expense".to_owned(),
            lines: vec![
                format!(
                    "本周收入 {}",
                    format_amount(decimal_from_f64(summary.week_trend.income), "¥")
                ),
                format!(
                    "本周支出 {}",
                    format_amount(decimal_from_f64(summary.week_trend.expense), "¥")
                ),
                format!(
                    "本周结余 {}",
                    format_amount(decimal_from_f64(summary.week_trend.balance), "¥")
                ),
            ],
        }],
    }
}

pub(crate) fn filter_diagnostics(
    semantic_ledger: &SemanticLedger,
    query: &RustDiagnosticQuery,
) -> Vec<RustLedgerDiagnostic> {
    semantic_ledger
        .diagnostics
        .iter()
        .filter(|diagnostic| {
            (diagnostic.blocking && query.include_blocking)
                || (!diagnostic.blocking && query.include_non_blocking)
        })
        .cloned()
        .collect()
}

fn build_account_node(
    builder: &AccountTreeBuilder,
    query_index: &QueryIndex,
) -> RustAccountNode {
    let lifecycle = query_index.account_lifecycles.get(&builder.full_path);
    let children = builder
        .children
        .values()
        .map(|child| build_account_node(child, query_index))
        .collect::<Vec<_>>();
    let subtitle = if children.is_empty() {
        if lifecycle.and_then(|item| item.close_date).is_some() {
            "已关闭".to_owned()
        } else {
            "活跃".to_owned()
        }
    } else {
        format!("{} 个子账户", children.len())
    };

    RustAccountNode {
        name: builder.name.clone(),
        subtitle,
        balance: format_balance_summary(
            &aggregate_account_prefix(&builder.full_path, &query_index.account_balances),
            false,
        ),
        is_closed: lifecycle.and_then(|item| item.close_date).is_some(),
        is_postable: lifecycle.is_some(),
        children,
    }
}

fn map_journal_entry(directive: &SemanticDirective) -> RustJournalEntry {
    match directive {
        SemanticDirective::Transaction(transaction) => {
            let ordered = ordered_postings_for_display(&transaction.postings);
            let primary = ordered
                .first()
                .map(|posting| posting.account.clone())
                .unwrap_or_default();
            let secondary = ordered
                .iter()
                .map(|posting| posting.account.clone())
                .find(|account| account != &primary);

            RustJournalEntry {
                date_iso8601: transaction.date_iso8601.clone(),
                entry_type: RustJournalEntryType::Transaction,
                title: transaction.title.clone(),
                primary_account: primary,
                secondary_account: secondary,
                detail: None,
                amount: select_display_amount(&ordered),
                status: None,
                transaction_flag: transaction.transaction_flag.clone(),
            }
        }
        SemanticDirective::Open(open) => RustJournalEntry {
            date_iso8601: open.date_iso8601.clone(),
            entry_type: RustJournalEntryType::Open,
            title: open.account.clone(),
            primary_account: open.account.clone(),
            secondary_account: None,
            detail: Some("账户已启用".to_owned()),
            amount: None,
            status: Some("已启用".to_owned()),
            transaction_flag: None,
        },
        SemanticDirective::Close(close) => RustJournalEntry {
            date_iso8601: close.date_iso8601.clone(),
            entry_type: RustJournalEntryType::Close,
            title: close.account.clone(),
            primary_account: close.account.clone(),
            secondary_account: None,
            detail: Some("账户已关闭".to_owned()),
            amount: None,
            status: Some("已关闭".to_owned()),
            transaction_flag: None,
        },
        SemanticDirective::Price(price) => RustJournalEntry {
            date_iso8601: price.date_iso8601.clone(),
            entry_type: RustJournalEntryType::Price,
            title: format!("{}/{}", price.base_commodity, price.amount.commodity),
            primary_account: format!("{}/{}", price.base_commodity, price.amount.commodity),
            secondary_account: None,
            detail: Some("价格记录".to_owned()),
            amount: Some(to_rust_amount(&price.amount)),
            status: None,
            transaction_flag: None,
        },
        SemanticDirective::Balance(balance) => RustJournalEntry {
            date_iso8601: balance.date_iso8601.clone(),
            entry_type: RustJournalEntryType::Balance,
            title: balance.account.clone(),
            primary_account: balance.account.clone(),
            secondary_account: None,
            detail: Some("余额断言".to_owned()),
            amount: Some(to_rust_amount(&balance.amount)),
            status: None,
            transaction_flag: None,
        },
    }
}

fn ordered_postings_for_display(postings: &[SemanticPosting]) -> Vec<&SemanticPosting> {
    let mut ordered = postings.iter().collect::<Vec<_>>();
    ordered.sort_by(|left, right| {
        account_display_score(&left.account)
            .cmp(&account_display_score(&right.account))
            .then_with(|| left.account.cmp(&right.account))
    });
    ordered
}

fn select_display_amount(postings: &[&SemanticPosting]) -> Option<RustAmount> {
    for posting in postings {
        let Some(amount) = &posting.amount else {
            continue;
        };
        let normalized_value = match account_root(&posting.account) {
            "Expenses" => -amount.value.abs(),
            "Income" => amount.value.abs(),
            "Liabilities" => -amount.value.abs(),
            _ => amount.value,
        };

        return Some(RustAmount {
            value: normalized_value.to_f64().unwrap_or_default(),
            commodity: amount.commodity.clone(),
            fraction_digits: amount.fraction_digits,
        });
    }
    None
}

fn build_trend_summary(
    label: &str,
    from: Date,
    to: Date,
    semantic_ledger: &SemanticLedger,
) -> RustTrendSummary {
    let mut income_by_commodity = BTreeMap::<String, Decimal>::new();
    let mut expense_by_commodity = BTreeMap::<String, Decimal>::new();

    for directive in &semantic_ledger.directives {
        let SemanticDirective::Transaction(transaction) = directive else {
            continue;
        };
        let Some(date) = parse_iso_date(&transaction.date_iso8601) else {
            continue;
        };
        if date < from || date >= to {
            continue;
        }

        for posting in &transaction.postings {
            let Some(amount) = &posting.amount else {
                continue;
            };
            let value = amount.value.abs();
            match account_root(&posting.account) {
                "Income" => {
                    *income_by_commodity
                        .entry(amount.commodity.clone())
                        .or_default() += value;
                }
                "Expenses" => {
                    *expense_by_commodity
                        .entry(amount.commodity.clone())
                        .or_default() += value;
                }
                _ => {}
            }
        }
    }

    let commodity = dominant_commodity(&income_by_commodity, &expense_by_commodity)
        .unwrap_or_else(|| "¥".to_owned());
    let income = income_by_commodity
        .get(&commodity)
        .cloned()
        .unwrap_or_default();
    let expense = expense_by_commodity
        .get(&commodity)
        .cloned()
        .unwrap_or_default();

    RustTrendSummary {
        chart_label: label.to_owned(),
        income: income.to_f64().unwrap_or_default(),
        expense: expense.to_f64().unwrap_or_default(),
        balance: (income - expense).to_f64().unwrap_or_default(),
    }
}

fn aggregate_account_type(
    root_type: &str,
    account_balances: &HashMap<String, BTreeMap<String, Decimal>>,
) -> BTreeMap<String, Decimal> {
    let mut totals = BTreeMap::<String, Decimal>::new();
    for (account, balances) in account_balances {
        if account_root(account) != root_type {
            continue;
        }
        for (commodity, value) in balances {
            *totals.entry(commodity.clone()).or_default() += *value;
        }
    }
    totals
}

fn aggregate_account_prefix(
    prefix: &str,
    account_balances: &HashMap<String, BTreeMap<String, Decimal>>,
) -> BTreeMap<String, Decimal> {
    let mut totals = BTreeMap::<String, Decimal>::new();
    for (account, balances) in account_balances {
        if account == prefix || account.starts_with(&format!("{prefix}:")) {
            for (commodity, value) in balances {
                *totals.entry(commodity.clone()).or_default() += *value;
            }
        }
    }
    totals
}

fn format_balance_summary(buckets: &BTreeMap<String, Decimal>, absolute: bool) -> String {
    if buckets.is_empty() {
        return "--".to_owned();
    }
    if buckets.len() == 1 {
        let (commodity, value) = buckets.iter().next().unwrap();
        return format_amount(if absolute { value.abs() } else { *value }, commodity);
    }
    format!("{} 币种", buckets.len())
}

fn format_amount(value: Decimal, commodity: &str) -> String {
    let is_negative = value.is_sign_negative();
    let absolute = value.abs();
    let digits = if absolute.fract().is_zero() { 0 } else { 2 };
    let normalized = absolute.round_dp(digits).normalize().to_string();
    let mut parts = normalized.split('.');
    let integer_part = group_thousands(parts.next().unwrap_or("0"));
    let number_text = if digits == 0 {
        integer_part
    } else {
        let fraction = parts.next().unwrap_or("00");
        format!("{integer_part}.{fraction:0<2}")
    };
    let sign = if is_negative { "- " } else { "" };
    format!("{sign}{commodity} {number_text}")
}

fn signed_amount_text(value: Decimal, commodity: &str) -> String {
    let sign = if value.is_sign_negative() { '-' } else { '+' };
    format!("{sign} {}", format_amount(value.abs(), commodity))
}

fn group_thousands(digits: &str) -> String {
    let mut buffer = String::new();
    for (index, digit) in digits.chars().enumerate() {
        let remaining = digits.len() - index;
        buffer.push(digit);
        if remaining > 1 && remaining % 3 == 1 {
            buffer.push(',');
        }
    }
    buffer
}

fn dominant_commodity(
    primary_buckets: &BTreeMap<String, Decimal>,
    fallback_buckets: &BTreeMap<String, Decimal>,
) -> Option<String> {
    let mut combined = BTreeMap::<String, Decimal>::new();
    for (commodity, value) in primary_buckets {
        *combined.entry(commodity.clone()).or_default() += value.abs();
    }
    for (commodity, value) in fallback_buckets {
        *combined.entry(commodity.clone()).or_default() += value.abs();
    }
    combined
        .into_iter()
        .max_by(|left, right| left.1.cmp(&right.1))
        .map(|entry| entry.0)
}

fn today_fallback() -> Date {
    Date::from_calendar_date(2026, Month::January, 1).expect("valid fallback date")
}

fn previous_month_start(reference_date: Date) -> Date {
    let year = if reference_date.month() == Month::January {
        reference_date.year() - 1
    } else {
        reference_date.year()
    };
    let month = if reference_date.month() == Month::January {
        Month::December
    } else {
        Month::try_from(reference_date.month() as u8 - 1).expect("valid month")
    };
    Date::from_calendar_date(year, month, 1).expect("valid previous month")
}

fn next_month_start(reference_date: Date) -> Date {
    let year = if reference_date.month() == Month::December {
        reference_date.year() + 1
    } else {
        reference_date.year()
    };
    let month = if reference_date.month() == Month::December {
        Month::January
    } else {
        Month::try_from(reference_date.month() as u8 + 1).expect("valid month")
    };
    Date::from_calendar_date(year, month, 1).expect("valid next month")
}

fn parse_iso_date(date_iso8601: &str) -> Option<Date> {
    let date = date_iso8601.get(0..10)?;
    let mut parts = date.split('-');
    let year = parts.next()?.parse::<i32>().ok()?;
    let month = parts.next()?.parse::<u8>().ok()?;
    let day = parts.next()?.parse::<u8>().ok()?;
    Date::from_calendar_date(year, Month::try_from(month).ok()?, day).ok()
}

fn decimal_from_f64(value: f64) -> Decimal {
    Decimal::from_f64_retain(value).unwrap_or_default()
}

fn account_root(account: &str) -> &str {
    account.split(':').next().unwrap_or_default()
}

fn account_display_score(account: &str) -> i32 {
    match account_root(account) {
        "Expenses" => 0,
        "Income" => 1,
        "Liabilities" => 2,
        "Assets" => 3,
        "Equity" => 4,
        _ => 5,
    }
}

fn to_rust_amount(amount: &crate::engine::semantic::SemanticAmount) -> RustAmount {
    RustAmount {
        value: amount.value.to_f64().unwrap_or_default(),
        commodity: amount.commodity.clone(),
        fraction_digits: amount.fraction_digits,
    }
}

#[derive(Clone, Debug)]
struct AccountTreeBuilder {
    name: String,
    full_path: String,
    children: BTreeMap<String, AccountTreeBuilder>,
}

impl AccountTreeBuilder {
    fn new(name: String, full_path: String) -> Self {
        Self {
            name,
            full_path,
            children: BTreeMap::new(),
        }
    }
}
