use std::collections::{BTreeMap, HashMap};
use std::str::FromStr;
use std::sync::LazyLock;

use regex::Regex;
use rust_decimal::Decimal;

use crate::api::{RustLedgerDiagnostic, RustTransactionFlag};
use crate::engine::ast::{
    AstBalanceDirective, AstCloseDirective, AstDirective, AstOpenDirective, AstPriceDirective,
    AstTransactionDirective,
};
use crate::engine::source::LedgerSourceSet;
use crate::engine::syntax::SyntaxTree;

static TITLE_OPTION_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^option\s+"title"\s+"((?:[^"\\]|\\.)*)"\s*(?:[;#].*)?$"#)
        .expect("valid title option regex")
});

static OPERATING_CURRENCY_OPTION_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^option\s+"operating_currency"\s+"((?:[^"\\]|\\.)*)"\s*(?:[;#].*)?$"#)
        .expect("valid operating_currency option regex")
});

#[derive(Clone, Debug, Default)]
pub(crate) struct SemanticLedger {
    pub(crate) ledger_id: String,
    pub(crate) ledger_name: String,
    pub(crate) operating_currencies: Vec<String>,
    pub(crate) loaded_file_count: i32,
    #[allow(dead_code)]
    pub(crate) documents: Vec<SemanticDocument>,
    pub(crate) directives: Vec<SemanticDirective>,
    pub(crate) account_lifecycles: BTreeMap<String, SemanticAccountLifecycle>,
    pub(crate) diagnostics: Vec<RustLedgerDiagnostic>,
    #[allow(dead_code)]
    pub(crate) is_fully_supported_for_queries: bool,
}

#[allow(dead_code)]
#[derive(Clone, Debug, Default)]
pub(crate) struct SemanticDocument {
    pub(crate) document_id: String,
    pub(crate) relative_path: String,
    pub(crate) is_entry: bool,
}

#[derive(Clone, Debug)]
pub(crate) enum SemanticDirective {
    Open(SemanticOpenDirective),
    Close(SemanticCloseDirective),
    Price(SemanticPriceDirective),
    Balance(SemanticBalanceDirective),
    Transaction(SemanticTransactionDirective),
}

impl SemanticDirective {
    pub(crate) fn date_iso8601(&self) -> &str {
        match self {
            Self::Open(directive) => &directive.date_iso8601,
            Self::Close(directive) => &directive.date_iso8601,
            Self::Price(directive) => &directive.date_iso8601,
            Self::Balance(directive) => &directive.date_iso8601,
            Self::Transaction(directive) => &directive.date_iso8601,
        }
    }

    pub(crate) fn source_location(&self) -> &str {
        match self {
            Self::Open(directive) => &directive.source_location,
            Self::Close(directive) => &directive.source_location,
            Self::Price(directive) => &directive.source_location,
            Self::Balance(directive) => &directive.source_location,
            Self::Transaction(directive) => &directive.source_location,
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticOpenDirective {
    pub(crate) date_iso8601: String,
    pub(crate) source_location: String,
    pub(crate) account: String,
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticCloseDirective {
    pub(crate) date_iso8601: String,
    pub(crate) source_location: String,
    pub(crate) account: String,
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticPriceDirective {
    pub(crate) date_iso8601: String,
    pub(crate) source_location: String,
    pub(crate) base_commodity: String,
    pub(crate) amount: SemanticAmount,
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticBalanceDirective {
    pub(crate) date_iso8601: String,
    pub(crate) source_location: String,
    pub(crate) account: String,
    pub(crate) amount: SemanticAmount,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct SemanticTransactionDirective {
    pub(crate) date_iso8601: String,
    pub(crate) source_location: String,
    pub(crate) title: String,
    pub(crate) transaction_flag: Option<RustTransactionFlag>,
    pub(crate) postings: Vec<SemanticPosting>,
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticPosting {
    pub(crate) account: String,
    pub(crate) amount: Option<SemanticAmount>,
}

#[derive(Clone, Debug)]
pub(crate) struct SemanticAmount {
    pub(crate) value: Decimal,
    pub(crate) commodity: String,
    pub(crate) fraction_digits: i32,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct SemanticAccountLifecycle {
    pub(crate) open_date: Option<String>,
    pub(crate) close_date: Option<String>,
    pub(crate) last_activity_date: Option<String>,
}

pub(crate) fn lower_syntax_tree(
    source_set: &LedgerSourceSet,
    syntax_tree: &SyntaxTree,
) -> SemanticLedger {
    let ledger_id = ledger_id_from_root(&source_set.root_path);
    let ledger_name = ledger_name_from_sources_or_root(source_set, &ledger_id);
    let operating_currencies = operating_currencies_from_sources(source_set);
    let mut ledger = SemanticLedger {
        ledger_id,
        ledger_name,
        operating_currencies,
        loaded_file_count: source_set.documents.len() as i32,
        documents: source_set
            .documents
            .iter()
            .map(|document| SemanticDocument {
                document_id: document.document_id.clone(),
                relative_path: document.relative_path.clone(),
                is_entry: document.is_entry,
            })
            .collect(),
        directives: Vec::new(),
        account_lifecycles: collect_declared_account_lifecycles(syntax_tree),
        diagnostics: syntax_tree
            .diagnostics
            .iter()
            .map(|diagnostic| RustLedgerDiagnostic {
                message: diagnostic.message.clone(),
                location: diagnostic.location.clone(),
                blocking: diagnostic.blocking,
            })
            .collect(),
        is_fully_supported_for_queries: !syntax_tree
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.blocking),
    };

    for document in &syntax_tree.ast.documents {
        for directive in &document.directives {
            match directive {
                AstDirective::Include(_) => {}
                AstDirective::Open(open_directive) => {
                    ledger.record_open(lower_open(open_directive));
                }
                AstDirective::Close(close_directive) => {
                    ledger.record_close(lower_close(close_directive));
                }
                AstDirective::Price(price_directive) => match lower_price(price_directive) {
                    Ok(price) => ledger.directives.push(SemanticDirective::Price(price)),
                    Err(diagnostic) => ledger.push_blocking_diagnostic(diagnostic),
                },
                AstDirective::Balance(balance_directive) => {
                    match lower_balance(balance_directive) {
                        Ok(balance) => ledger.record_balance(balance),
                        Err(diagnostic) => ledger.push_blocking_diagnostic(diagnostic),
                    }
                }
                AstDirective::Transaction(transaction_directive) => {
                    match lower_transaction(transaction_directive) {
                        Ok(transaction) => ledger.record_transaction(transaction),
                        Err(diagnostic) => ledger.push_blocking_diagnostic(diagnostic),
                    }
                }
            }
        }
    }

    ledger.finalize_validation();
    ledger.is_fully_supported_for_queries = !ledger.diagnostics.iter().any(|item| item.blocking);
    ledger
}

impl SemanticLedger {
    fn record_open(&mut self, directive: SemanticOpenDirective) {
        let lifecycle = self
            .account_lifecycles
            .entry(directive.account.clone())
            .or_default();
        if lifecycle.open_date.is_none() {
            lifecycle.open_date = Some(directive.date_iso8601.clone());
        }
        lifecycle.last_activity_date = Some(directive.date_iso8601.clone());
        self.directives.push(SemanticDirective::Open(directive));
    }

    fn record_close(&mut self, directive: SemanticCloseDirective) {
        let lifecycle = self
            .account_lifecycles
            .entry(directive.account.clone())
            .or_default();
        lifecycle.close_date = Some(directive.date_iso8601.clone());
        lifecycle.last_activity_date = Some(directive.date_iso8601.clone());
        self.directives.push(SemanticDirective::Close(directive));
    }

    fn record_balance(&mut self, directive: SemanticBalanceDirective) {
        self.touch_account(&directive.account, &directive.date_iso8601);
        self.directives.push(SemanticDirective::Balance(directive));
    }

    fn record_transaction(&mut self, directive: SemanticTransactionDirective) {
        for posting in &directive.postings {
            self.touch_account(&posting.account, &directive.date_iso8601);
        }
        self.directives
            .push(SemanticDirective::Transaction(directive));
    }

    fn touch_account(&mut self, account: &str, date_iso8601: &str) {
        let lifecycle = self
            .account_lifecycles
            .entry(account.to_owned())
            .or_default();
        lifecycle.last_activity_date = Some(date_iso8601.to_owned());
    }

    fn push_blocking_diagnostic(&mut self, diagnostic: RustLedgerDiagnostic) {
        self.is_fully_supported_for_queries = false;
        self.diagnostics.push(diagnostic);
    }

    fn finalize_validation(&mut self) {
        let directives = self.directives.clone();
        for directive in &directives {
            match directive {
                SemanticDirective::Transaction(transaction) => {
                    for posting in &transaction.postings {
                        self.validate_account_usage(
                            &posting.account,
                            &transaction.date_iso8601,
                            &transaction.source_location,
                        );
                    }
                }
                SemanticDirective::Balance(balance) => {
                    self.validate_account_usage(
                        &balance.account,
                        &balance.date_iso8601,
                        &balance.source_location,
                    );
                }
                SemanticDirective::Open(_)
                | SemanticDirective::Close(_)
                | SemanticDirective::Price(_) => {}
            }
        }

        for (account, lifecycle) in &self.account_lifecycles {
            if lifecycle.open_date.is_none() && lifecycle.close_date.is_some() {
                self.diagnostics.push(RustLedgerDiagnostic {
                    message: format!("账户未开户即关闭: {account}"),
                    location: account.clone(),
                    blocking: true,
                });
            }
            if let (Some(open_date), Some(close_date)) =
                (&lifecycle.open_date, &lifecycle.close_date)
            {
                if close_date < open_date {
                    self.diagnostics.push(RustLedgerDiagnostic {
                        message: format!("账户关闭日期早于开户日期: {account}"),
                        location: account.clone(),
                        blocking: true,
                    });
                }
            }
        }
    }

    fn validate_account_usage(&mut self, account: &str, date_iso8601: &str, source_location: &str) {
        let Some(lifecycle) = self.account_lifecycles.get(account) else {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: format!("未知账户: {account}"),
                location: source_location.to_owned(),
                blocking: true,
            });
            return;
        };

        let Some(open_date) = &lifecycle.open_date else {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: format!("未知账户: {account}"),
                location: source_location.to_owned(),
                blocking: true,
            });
            return;
        };

        let date = &date_iso8601[..10];
        if date < open_date.as_str() {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: format!("账户在开户前被引用: {account}"),
                location: source_location.to_owned(),
                blocking: true,
            });
        }

        if let Some(close_date) = &lifecycle.close_date {
            if date > close_date.as_str() {
                self.diagnostics.push(RustLedgerDiagnostic {
                    message: format!("账户在关闭后被引用: {account}"),
                    location: source_location.to_owned(),
                    blocking: true,
                });
            }
        }
    }
}

fn collect_declared_account_lifecycles(
    syntax_tree: &SyntaxTree,
) -> BTreeMap<String, SemanticAccountLifecycle> {
    let mut lifecycles = BTreeMap::<String, SemanticAccountLifecycle>::new();
    for document in &syntax_tree.ast.documents {
        for directive in &document.directives {
            match directive {
                AstDirective::Open(open) => {
                    let lifecycle = lifecycles.entry(open.account.clone()).or_default();
                    if lifecycle.open_date.is_none() {
                        lifecycle.open_date = Some(iso_date(&open.date));
                    }
                }
                AstDirective::Close(close) => {
                    lifecycles
                        .entry(close.account.clone())
                        .or_default()
                        .close_date = Some(iso_date(&close.date));
                }
                AstDirective::Include(_)
                | AstDirective::Price(_)
                | AstDirective::Balance(_)
                | AstDirective::Transaction(_) => {}
            }
        }
    }
    lifecycles
}

fn lower_open(directive: &AstOpenDirective) -> SemanticOpenDirective {
    SemanticOpenDirective {
        date_iso8601: iso_date(&directive.date),
        source_location: source_location(&directive.span),
        account: directive.account.clone(),
    }
}

fn lower_close(directive: &AstCloseDirective) -> SemanticCloseDirective {
    SemanticCloseDirective {
        date_iso8601: iso_date(&directive.date),
        source_location: source_location(&directive.span),
        account: directive.account.clone(),
    }
}

fn lower_price(
    directive: &AstPriceDirective,
) -> Result<SemanticPriceDirective, RustLedgerDiagnostic> {
    Ok(SemanticPriceDirective {
        date_iso8601: iso_date(&directive.date),
        source_location: source_location(&directive.span),
        base_commodity: directive.base_commodity.clone(),
        amount: lower_amount(&directive.amount, &directive.span)?,
    })
}

fn lower_balance(
    directive: &AstBalanceDirective,
) -> Result<SemanticBalanceDirective, RustLedgerDiagnostic> {
    Ok(SemanticBalanceDirective {
        date_iso8601: iso_date(&directive.date),
        source_location: source_location(&directive.span),
        account: directive.account.clone(),
        amount: lower_amount(&directive.amount, &directive.span)?,
    })
}

fn lower_transaction(
    directive: &AstTransactionDirective,
) -> Result<SemanticTransactionDirective, RustLedgerDiagnostic> {
    if directive.postings.len() < 2 {
        return Err(blocking_diagnostic(
            &directive.span,
            "Transaction 至少需要两条 postings",
        ));
    }

    let mut postings = directive
        .postings
        .iter()
        .map(|posting| {
            Ok(SemanticPosting {
                account: posting.account.clone(),
                amount: match &posting.amount {
                    Some(amount) => Some(lower_amount(amount, &posting.span)?),
                    None => None,
                },
            })
        })
        .collect::<Result<Vec<_>, RustLedgerDiagnostic>>()?;

    complete_postings_if_possible(&mut postings, &directive.span)?;

    Ok(SemanticTransactionDirective {
        date_iso8601: iso_date(&directive.date),
        source_location: source_location(&directive.span),
        title: directive.title.clone().unwrap_or_default(),
        transaction_flag: Some(if directive.flag == Some('!') {
            RustTransactionFlag::Pending
        } else {
            RustTransactionFlag::Cleared
        }),
        postings,
    })
}

fn complete_postings_if_possible(
    postings: &mut [SemanticPosting],
    span: &crate::engine::source::SourceSpan,
) -> Result<(), RustLedgerDiagnostic> {
    let missing_count = postings
        .iter()
        .filter(|posting| posting.amount.is_none())
        .count();
    if missing_count == 0 {
        validate_transaction_balance(postings, span)?;
        return Ok(());
    }

    if missing_count > 1 {
        return Err(blocking_diagnostic(
            span,
            "暂不支持一笔交易中存在多条自动补平 postings",
        ));
    }

    let mut explicit_totals = HashMap::<String, Decimal>::new();
    let mut template_fraction_digits = 0;
    for posting in postings.iter() {
        let Some(amount) = &posting.amount else {
            continue;
        };
        template_fraction_digits = amount.fraction_digits;
        *explicit_totals.entry(amount.commodity.clone()).or_default() += amount.value;
    }

    if explicit_totals.len() != 1 {
        return Err(blocking_diagnostic(
            span,
            "暂不支持多币种自动补平 transaction",
        ));
    }

    let (commodity, total) = explicit_totals.into_iter().next().unwrap();
    for posting in postings.iter_mut() {
        if posting.amount.is_none() {
            posting.amount = Some(SemanticAmount {
                value: -total,
                commodity: commodity.clone(),
                fraction_digits: template_fraction_digits,
            });
        }
    }

    Ok(())
}

fn validate_transaction_balance(
    postings: &[SemanticPosting],
    span: &crate::engine::source::SourceSpan,
) -> Result<(), RustLedgerDiagnostic> {
    let mut totals = HashMap::<String, Decimal>::new();
    for posting in postings {
        let Some(amount) = &posting.amount else {
            continue;
        };
        *totals.entry(amount.commodity.clone()).or_default() += amount.value;
    }

    if totals.values().all(Decimal::is_zero) {
        Ok(())
    } else {
        Err(blocking_diagnostic(span, "Transaction 不平衡"))
    }
}

fn lower_amount(
    amount: &crate::engine::ast::AstAmount,
    span: &crate::engine::source::SourceSpan,
) -> Result<SemanticAmount, RustLedgerDiagnostic> {
    let value =
        Decimal::from_str(&amount.value).map_err(|_| blocking_diagnostic(span, "无法解析金额"))?;
    Ok(SemanticAmount {
        value,
        commodity: amount.commodity.clone(),
        fraction_digits: fraction_digits(&amount.value),
    })
}

fn blocking_diagnostic(
    span: &crate::engine::source::SourceSpan,
    message: &str,
) -> RustLedgerDiagnostic {
    RustLedgerDiagnostic {
        message: message.to_owned(),
        location: source_location(span),
        blocking: true,
    }
}

fn source_location(span: &crate::engine::source::SourceSpan) -> String {
    format!("{}:{}", span.document_id, span.line)
}

fn fraction_digits(numeric_text: &str) -> i32 {
    numeric_text
        .find('.')
        .map(|dot_index| (numeric_text.len() - dot_index - 1) as i32)
        .unwrap_or(0)
}

fn iso_date(date: &str) -> String {
    format!("{date}T00:00:00.000")
}

fn ledger_id_from_root(root_path: &std::path::Path) -> String {
    root_path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("ledger")
        .to_owned()
}

fn ledger_name_from_root(ledger_id: &str) -> String {
    ledger_id
        .replace(['_', '-'], " ")
        .split_whitespace()
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn ledger_name_from_sources_or_root(source_set: &LedgerSourceSet, ledger_id: &str) -> String {
    ledger_title_from_sources(source_set)
        .filter(|title| !title.trim().is_empty())
        .unwrap_or_else(|| ledger_name_from_root(ledger_id))
}

fn ledger_title_from_sources(source_set: &LedgerSourceSet) -> Option<String> {
    let entry_document = source_set
        .documents
        .iter()
        .find(|document| document.document_id == source_set.entry_document_id);
    if let Some(title) = entry_document.and_then(|document| parse_title_option(&document.content)) {
        return Some(title);
    }

    source_set
        .documents
        .iter()
        .filter(|document| document.document_id != source_set.entry_document_id)
        .find_map(|document| parse_title_option(&document.content))
}

fn parse_title_option(content: &str) -> Option<String> {
    content
        .lines()
        .map(str::trim)
        .map(|line| line.trim_start_matches('\u{feff}'))
        .filter(|line| !line.is_empty() && !line.starts_with(';') && !line.starts_with('#'))
        .find_map(|line| {
            TITLE_OPTION_RE
                .captures(line)
                .and_then(|captures| captures.get(1).map(|value| value.as_str().to_owned()))
        })
}

fn operating_currencies_from_sources(source_set: &LedgerSourceSet) -> Vec<String> {
    let mut currencies = Vec::new();
    for document in &source_set.documents {
        for line in document.content.lines() {
            let normalized = line.trim().trim_start_matches('\u{feff}');
            if normalized.is_empty() || normalized.starts_with(';') || normalized.starts_with('#') {
                continue;
            }
            if let Some(captures) = OPERATING_CURRENCY_OPTION_RE.captures(normalized) {
                if let Some(value) = captures.get(1) {
                    let currency = value.as_str().to_owned();
                    if !currencies.contains(&currency) {
                        currencies.push(currency);
                    }
                }
            }
        }
    }
    currencies
}
