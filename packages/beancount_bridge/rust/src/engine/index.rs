use std::collections::{BTreeMap, HashMap};

use rust_decimal::Decimal;
use time::{Date, Month};

use crate::engine::semantic::{SemanticDirective, SemanticLedger};

#[derive(Clone, Debug, Default)]
pub(crate) struct QueryIndex {
    pub(crate) account_lifecycles: BTreeMap<String, IndexedAccountLifecycle>,
    pub(crate) account_balances: HashMap<String, BTreeMap<String, Decimal>>,
    pub(crate) journal_order: Vec<usize>,
    pub(crate) latest_reference_date: Option<Date>,
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct IndexedAccountLifecycle {
    pub(crate) open_date: Option<Date>,
    pub(crate) close_date: Option<Date>,
    #[allow(dead_code)]
    pub(crate) last_activity_date: Option<Date>,
}

pub(crate) fn build_query_index(semantic_ledger: &SemanticLedger) -> QueryIndex {
    let mut index = QueryIndex {
        account_lifecycles: semantic_ledger
            .account_lifecycles
            .iter()
            .map(|(account, lifecycle)| {
                (
                    account.clone(),
                    IndexedAccountLifecycle {
                        open_date: parse_iso_date_option(lifecycle.open_date.as_deref()),
                        close_date: parse_iso_date_option(lifecycle.close_date.as_deref()),
                        last_activity_date: parse_iso_date_option(
                            lifecycle.last_activity_date.as_deref(),
                        ),
                    },
                )
            })
            .collect(),
        ..QueryIndex::default()
    };

    for directive in &semantic_ledger.directives {
        let date = parse_iso_date(directive.date_iso8601());
        if date > index.latest_reference_date {
            index.latest_reference_date = date;
        }

        if let SemanticDirective::Transaction(transaction) = directive {
            for posting in &transaction.postings {
                let Some(amount) = &posting.amount else {
                    continue;
                };
                let balances = index
                    .account_balances
                    .entry(posting.account.clone())
                    .or_default();
                *balances.entry(amount.commodity.clone()).or_default() += amount.value;
            }
        }
    }

    index.journal_order = (0..semantic_ledger.directives.len()).collect();
    index.journal_order.sort_by(|left, right| {
        let left_directive = &semantic_ledger.directives[*left];
        let right_directive = &semantic_ledger.directives[*right];
        right_directive
            .date_iso8601()
            .cmp(left_directive.date_iso8601())
            .then_with(|| {
                right_directive
                    .source_location()
                    .cmp(left_directive.source_location())
            })
    });

    index
}

impl QueryIndex {
    pub(crate) fn open_account_count(&self) -> i32 {
        self.account_lifecycles
            .values()
            .filter(|lifecycle| lifecycle.open_date.is_some())
            .count() as i32
    }

    pub(crate) fn closed_account_count(&self) -> i32 {
        self.account_lifecycles
            .values()
            .filter(|lifecycle| lifecycle.close_date.is_some())
            .count() as i32
    }
}

fn parse_iso_date_option(value: Option<&str>) -> Option<Date> {
    value.and_then(parse_iso_date)
}

fn parse_iso_date(date_iso8601: &str) -> Option<Date> {
    let date = date_iso8601.get(0..10)?;
    let mut parts = date.split('-');
    let year = parts.next()?.parse::<i32>().ok()?;
    let month = parts.next()?.parse::<u8>().ok()?;
    let day = parts.next()?.parse::<u8>().ok()?;
    Date::from_calendar_date(year, Month::try_from(month).ok()?, day).ok()
}
