#![allow(dead_code)]

use crate::engine::source::SourceSpan;

#[derive(Clone, Debug, Default)]
pub(crate) struct AstLedger {
    pub(crate) documents: Vec<AstDocument>,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct AstDocument {
    pub(crate) document_id: String,
    pub(crate) directives: Vec<AstDirective>,
}

#[derive(Clone, Debug)]
pub(crate) enum AstDirective {
    Include(AstIncludeDirective),
    Open(AstOpenDirective),
    Close(AstCloseDirective),
    Price(AstPriceDirective),
    Balance(AstBalanceDirective),
    Transaction(AstTransactionDirective),
}

#[derive(Clone, Debug)]
pub(crate) struct AstIncludeDirective {
    pub(crate) span: SourceSpan,
    pub(crate) path: String,
}

#[derive(Clone, Debug)]
pub(crate) struct AstOpenDirective {
    pub(crate) span: SourceSpan,
    pub(crate) date: String,
    pub(crate) account: String,
    pub(crate) commodities: Vec<String>,
}

#[derive(Clone, Debug)]
pub(crate) struct AstCloseDirective {
    pub(crate) span: SourceSpan,
    pub(crate) date: String,
    pub(crate) account: String,
}

#[derive(Clone, Debug)]
pub(crate) struct AstPriceDirective {
    pub(crate) span: SourceSpan,
    pub(crate) date: String,
    pub(crate) base_commodity: String,
    pub(crate) amount: AstAmount,
}

#[derive(Clone, Debug)]
pub(crate) struct AstBalanceDirective {
    pub(crate) span: SourceSpan,
    pub(crate) date: String,
    pub(crate) account: String,
    pub(crate) amount: AstAmount,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct AstTransactionDirective {
    pub(crate) span: SourceSpan,
    pub(crate) date: String,
    pub(crate) flag: Option<char>,
    pub(crate) title: Option<String>,
    pub(crate) postings: Vec<AstPosting>,
}

#[derive(Clone, Debug)]
pub(crate) struct AstPosting {
    pub(crate) span: SourceSpan,
    pub(crate) account: String,
    pub(crate) amount: Option<AstAmount>,
}

#[derive(Clone, Debug)]
pub(crate) struct AstAmount {
    pub(crate) value: String,
    pub(crate) commodity: String,
}
