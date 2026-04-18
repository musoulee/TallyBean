#![allow(dead_code)]

use crate::engine::source::SourceSpan;

#[derive(Clone, Debug, Default)]
pub(crate) struct CstLedger {
    pub(crate) documents: Vec<CstDocument>,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct CstDocument {
    pub(crate) document_id: String,
    pub(crate) items: Vec<CstItem>,
}

#[derive(Clone, Debug)]
pub(crate) enum CstItem {
    Include(CstIncludeItem),
    Open(CstOpenItem),
    Close(CstCloseItem),
    Price(CstPriceItem),
    Balance(CstBalanceItem),
    Transaction(CstTransactionItem),
    Unsupported(CstUnsupportedItem),
    Error(CstErrorItem),
}

#[derive(Clone, Debug)]
pub(crate) struct CstIncludeItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstOpenItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstCloseItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstPriceItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstBalanceItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstTransactionItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw_header: String,
    pub(crate) raw_postings: Vec<String>,
}

#[derive(Clone, Debug)]
pub(crate) struct CstUnsupportedItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
    pub(crate) message: String,
}

#[derive(Clone, Debug)]
pub(crate) struct CstErrorItem {
    pub(crate) span: SourceSpan,
    pub(crate) raw: String,
    pub(crate) message: String,
}
