use rust_decimal::prelude::ToPrimitive;

use crate::api::{
    RustAmount, RustLedgerDirective, RustLedgerDirectiveKind, RustLedgerSnapshot, RustPosting,
};
use crate::engine::semantic::{lower_syntax_tree, SemanticDirective, SemanticLedger};
use crate::engine::source::load_ledger_source;
use crate::engine::syntax::parse_source_set;

pub(crate) fn parse_ledger_snapshot(root_path: &str, entry_file_path: &str) -> RustLedgerSnapshot {
    let source_set = load_ledger_source(root_path, entry_file_path);
    let syntax_tree = parse_source_set(&source_set);
    let semantic_ledger = lower_syntax_tree(&source_set, &syntax_tree);
    build_compat_snapshot(&semantic_ledger)
}

pub(crate) fn build_compat_snapshot(semantic_ledger: &SemanticLedger) -> RustLedgerSnapshot {
    RustLedgerSnapshot {
        ledger_id: semantic_ledger.ledger_id.clone(),
        ledger_name: semantic_ledger.ledger_name.clone(),
        loaded_file_count: semantic_ledger.loaded_file_count,
        directives: semantic_ledger
            .directives
            .iter()
            .map(map_directive)
            .collect(),
        diagnostics: semantic_ledger.diagnostics.clone(),
    }
}

fn map_directive(directive: &SemanticDirective) -> RustLedgerDirective {
    match directive {
        SemanticDirective::Open(open) => RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Open,
            date_iso8601: open.date_iso8601.clone(),
            source_location: open.source_location.clone(),
            account: Some(open.account.clone()),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: None,
            postings: Vec::new(),
        },
        SemanticDirective::Close(close) => RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Close,
            date_iso8601: close.date_iso8601.clone(),
            source_location: close.source_location.clone(),
            account: Some(close.account.clone()),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: None,
            postings: Vec::new(),
        },
        SemanticDirective::Price(price) => RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Price,
            date_iso8601: price.date_iso8601.clone(),
            source_location: price.source_location.clone(),
            account: None,
            title: None,
            base_commodity: Some(price.base_commodity.clone()),
            quote_commodity: Some(price.amount.commodity.clone()),
            amount: Some(map_amount(&price.amount)),
            transaction_flag: None,
            postings: Vec::new(),
        },
        SemanticDirective::Balance(balance) => RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Balance,
            date_iso8601: balance.date_iso8601.clone(),
            source_location: balance.source_location.clone(),
            account: Some(balance.account.clone()),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: Some(map_amount(&balance.amount)),
            transaction_flag: None,
            postings: Vec::new(),
        },
        SemanticDirective::Transaction(transaction) => RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Transaction,
            date_iso8601: transaction.date_iso8601.clone(),
            source_location: transaction.source_location.clone(),
            account: None,
            title: Some(transaction.title.clone()),
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: transaction.transaction_flag.clone(),
            postings: transaction
                .postings
                .iter()
                .map(|posting| RustPosting {
                    account: posting.account.clone(),
                    amount: posting.amount.as_ref().map(map_amount),
                })
                .collect(),
        },
    }
}

fn map_amount(amount: &crate::engine::semantic::SemanticAmount) -> RustAmount {
    RustAmount {
        value: amount.value.to_f64().unwrap_or_default(),
        commodity: amount.commodity.clone(),
        fraction_digits: amount.fraction_digits,
    }
}
