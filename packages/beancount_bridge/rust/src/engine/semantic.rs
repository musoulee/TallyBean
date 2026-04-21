use std::collections::{BTreeMap, HashMap};
use std::str::FromStr;
use std::sync::LazyLock;

use regex::Regex;
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;

use crate::api::{
    RustAmount, RustLedgerDiagnostic, RustLedgerDirective, RustLedgerDirectiveKind,
    RustLedgerSnapshot, RustPosting, RustTransactionFlag,
};
use crate::engine::ast::{
    AstBalanceDirective, AstCloseDirective, AstDirective, AstOpenDirective, AstPriceDirective,
    AstTransactionDirective,
};
use crate::engine::source::WorkspaceSourceSet;
use crate::engine::syntax::SyntaxTree;

static TITLE_OPTION_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^option\s+"title"\s+"((?:[^"\\]|\\.)*)"\s*(?:[;#].*)?$"#)
        .expect("valid title option regex")
});

#[derive(Clone, Debug, Default)]
pub(crate) struct SemanticLedger {
    pub(crate) workspace_id: String,
    pub(crate) workspace_name: String,
    pub(crate) loaded_file_count: i32,
    #[allow(dead_code)]
    pub(crate) documents: Vec<SemanticDocument>,
    pub(crate) directives: Vec<SemanticDirective>,
    pub(crate) account_lifecycles: BTreeMap<String, SemanticAccountLifecycle>,
    pub(crate) diagnostics: Vec<RustLedgerDiagnostic>,
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
    source_set: &WorkspaceSourceSet,
    syntax_tree: &SyntaxTree,
) -> SemanticLedger {
    let workspace_id = workspace_id_from_root(&source_set.root_path);
    let workspace_name = workspace_name_from_sources_or_root(source_set, &workspace_id);
    let mut ledger = SemanticLedger {
        workspace_id,
        workspace_name,
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
        account_lifecycles: BTreeMap::new(),
        diagnostics: syntax_tree
            .diagnostics
            .iter()
            .map(|diagnostic| RustLedgerDiagnostic {
                message: diagnostic.message.clone(),
                location: diagnostic.location.clone(),
                blocking: diagnostic.blocking,
            })
            .collect(),
        is_fully_supported_for_queries: syntax_tree.diagnostics.is_empty(),
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

    ledger
}

impl SemanticLedger {
    pub(crate) fn projection_snapshot(&self) -> RustLedgerSnapshot {
        RustLedgerSnapshot {
            workspace_id: self.workspace_id.clone(),
            workspace_name: self.workspace_name.clone(),
            loaded_file_count: self.loaded_file_count,
            directives: self
                .directives
                .iter()
                .map(SemanticDirective::to_rust_directive)
                .collect(),
            diagnostics: self.diagnostics.clone(),
        }
    }

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
}

impl SemanticDirective {
    fn to_rust_directive(&self) -> RustLedgerDirective {
        match self {
            SemanticDirective::Open(directive) => RustLedgerDirective {
                kind: RustLedgerDirectiveKind::Open,
                date_iso8601: directive.date_iso8601.clone(),
                source_location: directive.source_location.clone(),
                account: Some(directive.account.clone()),
                title: None,
                base_commodity: None,
                quote_commodity: None,
                amount: None,
                transaction_flag: None,
                postings: Vec::new(),
            },
            SemanticDirective::Close(directive) => RustLedgerDirective {
                kind: RustLedgerDirectiveKind::Close,
                date_iso8601: directive.date_iso8601.clone(),
                source_location: directive.source_location.clone(),
                account: Some(directive.account.clone()),
                title: None,
                base_commodity: None,
                quote_commodity: None,
                amount: None,
                transaction_flag: None,
                postings: Vec::new(),
            },
            SemanticDirective::Price(directive) => RustLedgerDirective {
                kind: RustLedgerDirectiveKind::Price,
                date_iso8601: directive.date_iso8601.clone(),
                source_location: directive.source_location.clone(),
                account: None,
                title: None,
                base_commodity: Some(directive.base_commodity.clone()),
                quote_commodity: Some(directive.amount.commodity.clone()),
                amount: Some(directive.amount.to_rust_amount()),
                transaction_flag: None,
                postings: Vec::new(),
            },
            SemanticDirective::Balance(directive) => RustLedgerDirective {
                kind: RustLedgerDirectiveKind::Balance,
                date_iso8601: directive.date_iso8601.clone(),
                source_location: directive.source_location.clone(),
                account: Some(directive.account.clone()),
                title: None,
                base_commodity: None,
                quote_commodity: None,
                amount: Some(directive.amount.to_rust_amount()),
                transaction_flag: None,
                postings: Vec::new(),
            },
            SemanticDirective::Transaction(directive) => RustLedgerDirective {
                kind: RustLedgerDirectiveKind::Transaction,
                date_iso8601: directive.date_iso8601.clone(),
                source_location: directive.source_location.clone(),
                account: None,
                title: Some(directive.title.clone()),
                base_commodity: None,
                quote_commodity: None,
                amount: None,
                transaction_flag: directive.transaction_flag.clone(),
                postings: directive
                    .postings
                    .iter()
                    .map(|posting| RustPosting {
                        account: posting.account.clone(),
                        amount: posting.amount.as_ref().map(SemanticAmount::to_rust_amount),
                    })
                    .collect(),
            },
        }
    }
}

impl SemanticAmount {
    fn to_rust_amount(&self) -> RustAmount {
        RustAmount {
            value: self.value.to_f64().unwrap_or_default(),
            commodity: self.commodity.clone(),
            fraction_digits: self.fraction_digits,
        }
    }
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

fn workspace_id_from_root(root_path: &std::path::Path) -> String {
    root_path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("workspace")
        .to_owned()
}

fn workspace_name_from_root(workspace_id: &str) -> String {
    workspace_id
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

fn workspace_name_from_sources_or_root(
    source_set: &WorkspaceSourceSet,
    workspace_id: &str,
) -> String {
    workspace_title_from_sources(source_set)
        .filter(|title| !title.trim().is_empty())
        .unwrap_or_else(|| workspace_name_from_root(workspace_id))
}

fn workspace_title_from_sources(source_set: &WorkspaceSourceSet) -> Option<String> {
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
