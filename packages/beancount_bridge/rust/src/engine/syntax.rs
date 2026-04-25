#![allow(dead_code)]

use logos::Logos;

use crate::engine::ast::{
    AstAmount, AstBalanceDirective, AstCloseDirective, AstDirective, AstDocument,
    AstIncludeDirective, AstLedger, AstOpenDirective, AstPosting, AstPriceDirective,
    AstTransactionDirective,
};
use crate::engine::cst::{
    CstBalanceItem, CstCloseItem, CstDocument, CstErrorItem, CstIncludeItem, CstItem, CstLedger,
    CstOpenItem, CstPriceItem, CstTransactionItem, CstUnsupportedItem,
};
use crate::engine::source::{LedgerSourceSet, SourceDiagnostic, SourceSpan};

const KNOWN_UNSUPPORTED_DATED_DIRECTIVES: &[&str] = &[
    "commodity",
    "pad",
    "note",
    "document",
    "event",
    "query",
    "custom",
];

#[derive(Clone, Debug, Default)]
pub(crate) struct SyntaxTree {
    pub(crate) cst: CstLedger,
    pub(crate) ast: AstLedger,
    pub(crate) diagnostics: Vec<SourceDiagnostic>,
}

pub(crate) fn parse_source_set(source_set: &LedgerSourceSet) -> SyntaxTree {
    let mut parser = SyntaxParser::new(source_set.diagnostics.clone());
    for document in &source_set.documents {
        parser.parse_document(document.document_id.clone(), &document.content);
    }
    parser.finish()
}

struct SyntaxParser {
    cst_documents: Vec<CstDocument>,
    ast_documents: Vec<AstDocument>,
    diagnostics: Vec<SourceDiagnostic>,
}

impl SyntaxParser {
    fn new(diagnostics: Vec<SourceDiagnostic>) -> Self {
        Self {
            cst_documents: Vec::new(),
            ast_documents: Vec::new(),
            diagnostics,
        }
    }

    fn parse_document(&mut self, document_id: String, content: &str) {
        let lines = content.lines().collect::<Vec<_>>();
        let mut cst_items = Vec::new();
        let mut ast_directives = Vec::new();
        let mut index = 0usize;

        while index < lines.len() {
            let raw_line = lines[index];
            let trimmed = raw_line.trim();
            if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.starts_with('#') {
                index += 1;
                continue;
            }

            let line_number = index + 1;
            if trimmed.starts_with("include ") {
                let span = span_for_line(&document_id, line_number, raw_line);
                match parse_include(trimmed) {
                    Ok(path) => {
                        cst_items.push(CstItem::Include(CstIncludeItem {
                            span: span.clone(),
                            raw: raw_line.to_owned(),
                        }));
                        ast_directives
                            .push(AstDirective::Include(AstIncludeDirective { span, path }));
                    }
                    Err(message) => {
                        self.push_error(
                            &document_id,
                            line_number,
                            raw_line,
                            &message,
                            &mut cst_items,
                        );
                    }
                }
                index += 1;
                continue;
            }

            if !is_dated_directive(trimmed) {
                index += 1;
                continue;
            }

            if let Some(keyword) = unsupported_dated_directive_keyword(trimmed) {
                self.push_unsupported(
                    &document_id,
                    line_number,
                    raw_line,
                    &format!("暂不支持 {keyword} 指令"),
                    &mut cst_items,
                );
                index += 1;
                continue;
            }

            if is_open_directive(trimmed) {
                let span = span_for_line(&document_id, line_number, raw_line);
                match parse_open(trimmed, span.clone()) {
                    Ok(open_directive) => {
                        cst_items.push(CstItem::Open(CstOpenItem {
                            span,
                            raw: raw_line.to_owned(),
                        }));
                        ast_directives.push(AstDirective::Open(open_directive));
                    }
                    Err(message) => {
                        self.push_error(
                            &document_id,
                            line_number,
                            raw_line,
                            &message,
                            &mut cst_items,
                        );
                    }
                }
                index += 1;
                continue;
            }

            if is_close_directive(trimmed) {
                let span = span_for_line(&document_id, line_number, raw_line);
                match parse_close(trimmed, span.clone()) {
                    Ok(close_directive) => {
                        cst_items.push(CstItem::Close(CstCloseItem {
                            span,
                            raw: raw_line.to_owned(),
                        }));
                        ast_directives.push(AstDirective::Close(close_directive));
                    }
                    Err(message) => {
                        self.push_error(
                            &document_id,
                            line_number,
                            raw_line,
                            &message,
                            &mut cst_items,
                        );
                    }
                }
                index += 1;
                continue;
            }

            if is_price_directive(trimmed) {
                let span = span_for_line(&document_id, line_number, raw_line);
                match parse_price(trimmed, span.clone()) {
                    Ok(price_directive) => {
                        cst_items.push(CstItem::Price(CstPriceItem {
                            span,
                            raw: raw_line.to_owned(),
                        }));
                        ast_directives.push(AstDirective::Price(price_directive));
                    }
                    Err(message) => {
                        self.push_error(
                            &document_id,
                            line_number,
                            raw_line,
                            &message,
                            &mut cst_items,
                        );
                    }
                }
                index += 1;
                continue;
            }

            if is_balance_directive(trimmed) {
                let span = span_for_line(&document_id, line_number, raw_line);
                match parse_balance(trimmed, span.clone()) {
                    Ok(balance_directive) => {
                        cst_items.push(CstItem::Balance(CstBalanceItem {
                            span,
                            raw: raw_line.to_owned(),
                        }));
                        ast_directives.push(AstDirective::Balance(balance_directive));
                    }
                    Err(message) => {
                        self.push_error(
                            &document_id,
                            line_number,
                            raw_line,
                            &message,
                            &mut cst_items,
                        );
                    }
                }
                index += 1;
                continue;
            }

            let header_line_number = line_number;
            let mut raw_postings = Vec::new();
            while index + 1 < lines.len()
                && (lines[index + 1].starts_with(' ') || lines[index + 1].starts_with('\t'))
            {
                index += 1;
                raw_postings.push(lines[index].to_owned());
            }

            let span = span_for_line(&document_id, header_line_number, raw_line);
            match parse_transaction(trimmed, &document_id, header_line_number, &raw_postings) {
                Ok(transaction) => {
                    cst_items.push(CstItem::Transaction(CstTransactionItem {
                        span,
                        raw_header: raw_line.to_owned(),
                        raw_postings,
                    }));
                    ast_directives.push(AstDirective::Transaction(transaction));
                }
                Err(message) => {
                    self.push_error(
                        &document_id,
                        header_line_number,
                        raw_line,
                        &message,
                        &mut cst_items,
                    );
                }
            }
            index += 1;
        }

        self.cst_documents.push(CstDocument {
            document_id: document_id.clone(),
            items: cst_items,
        });
        self.ast_documents.push(AstDocument {
            document_id,
            directives: ast_directives,
        });
    }

    fn finish(self) -> SyntaxTree {
        SyntaxTree {
            cst: CstLedger {
                documents: self.cst_documents,
            },
            ast: AstLedger {
                documents: self.ast_documents,
            },
            diagnostics: self.diagnostics,
        }
    }

    fn push_error(
        &mut self,
        document_id: &str,
        line: usize,
        raw_line: &str,
        message: &str,
        cst_items: &mut Vec<CstItem>,
    ) {
        let span = span_for_line(document_id, line, raw_line);
        self.diagnostics.push(SourceDiagnostic {
            message: message.to_owned(),
            location: format!("{document_id}:{line}"),
            blocking: true,
        });
        cst_items.push(CstItem::Error(CstErrorItem {
            span,
            raw: raw_line.to_owned(),
            message: message.to_owned(),
        }));
    }

    fn push_unsupported(
        &mut self,
        document_id: &str,
        line: usize,
        raw_line: &str,
        message: &str,
        cst_items: &mut Vec<CstItem>,
    ) {
        let span = span_for_line(document_id, line, raw_line);
        self.diagnostics.push(SourceDiagnostic {
            message: message.to_owned(),
            location: format!("{document_id}:{line}"),
            blocking: false,
        });
        cst_items.push(CstItem::Unsupported(CstUnsupportedItem {
            span,
            raw: raw_line.to_owned(),
            message: message.to_owned(),
        }));
    }
}

fn parse_include(input: &str) -> Result<String, String> {
    let tokens = lex_line(input);
    match tokens.as_slice() {
        [LexedToken {
            token: SyntaxToken::Include,
            ..
        }, LexedToken {
            token: SyntaxToken::QuotedString,
            slice,
            ..
        }] => Ok(unquote(slice)),
        _ => Err("无法解析 include 指令".to_owned()),
    }
}

fn parse_open(input: &str, span: SourceSpan) -> Result<AstOpenDirective, String> {
    let tokens = lex_line(input);
    if tokens.len() < 3 {
        return Err("无法解析 open 指令".to_owned());
    }

    match (&tokens[0].token, &tokens[1].token, &tokens[2].token) {
        (SyntaxToken::Date, SyntaxToken::Open, SyntaxToken::Identifier) => Ok(AstOpenDirective {
            span,
            date: tokens[0].slice.to_owned(),
            account: tokens[2].slice.to_owned(),
            commodities: tokens[3..]
                .iter()
                .filter(|token| token.token == SyntaxToken::Identifier)
                .map(|token| token.slice.to_owned())
                .collect(),
        }),
        _ => Err("无法解析 open 指令".to_owned()),
    }
}

fn parse_close(input: &str, span: SourceSpan) -> Result<AstCloseDirective, String> {
    let tokens = lex_line(input);
    match tokens.as_slice() {
        [LexedToken {
            token: SyntaxToken::Date,
            slice: date,
            ..
        }, LexedToken {
            token: SyntaxToken::Close,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: account,
            ..
        }, ..] => Ok(AstCloseDirective {
            span,
            date: (*date).to_owned(),
            account: (*account).to_owned(),
        }),
        _ => Err("无法解析 close 指令".to_owned()),
    }
}

fn parse_price(input: &str, span: SourceSpan) -> Result<AstPriceDirective, String> {
    let tokens = lex_line(input);
    match tokens.as_slice() {
        [LexedToken {
            token: SyntaxToken::Date,
            slice: date,
            ..
        }, LexedToken {
            token: SyntaxToken::Price,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: base_commodity,
            ..
        }, LexedToken {
            token: SyntaxToken::Number,
            slice: value,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: quote_commodity,
            ..
        }, ..] => Ok(AstPriceDirective {
            span,
            date: (*date).to_owned(),
            base_commodity: (*base_commodity).to_owned(),
            amount: AstAmount {
                value: (*value).to_owned(),
                commodity: (*quote_commodity).to_owned(),
            },
        }),
        _ => Err("无法解析 price 指令".to_owned()),
    }
}

fn parse_balance(input: &str, span: SourceSpan) -> Result<AstBalanceDirective, String> {
    let tokens = lex_line(input);
    match tokens.as_slice() {
        [LexedToken {
            token: SyntaxToken::Date,
            slice: date,
            ..
        }, LexedToken {
            token: SyntaxToken::Balance,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: account,
            ..
        }, LexedToken {
            token: SyntaxToken::Number,
            slice: value,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: commodity,
            ..
        }, ..] => Ok(AstBalanceDirective {
            span,
            date: (*date).to_owned(),
            account: (*account).to_owned(),
            amount: AstAmount {
                value: (*value).to_owned(),
                commodity: (*commodity).to_owned(),
            },
        }),
        _ => Err("无法解析 balance 指令".to_owned()),
    }
}

fn parse_transaction(
    input: &str,
    document_id: &str,
    line: usize,
    posting_lines: &[String],
) -> Result<AstTransactionDirective, String> {
    let tokens = lex_line(input);
    if tokens.is_empty() {
        return Err("无法解析 transaction 指令".to_owned());
    }

    let date = match tokens.first() {
        Some(LexedToken {
            token: SyntaxToken::Date,
            slice,
            ..
        }) => (*slice).to_owned(),
        _ => return Err("无法解析 transaction 指令".to_owned()),
    };
    let flag = match tokens.get(1) {
        Some(LexedToken {
            token: SyntaxToken::Star,
            ..
        }) => Some('*'),
        Some(LexedToken {
            token: SyntaxToken::Bang,
            ..
        }) => Some('!'),
        _ => None,
    };
    let title = tokens
        .iter()
        .find(|token| token.token == SyntaxToken::QuotedString)
        .map(|token| unquote(token.slice));

    let postings = posting_lines
        .iter()
        .enumerate()
        .filter(|(_, posting)| !is_transaction_metadata_line(posting))
        .map(|(offset, posting)| parse_posting(document_id, line + offset + 1, posting))
        .collect::<Result<Vec<_>, _>>()?;

    Ok(AstTransactionDirective {
        span: span_for_line(document_id, line, input),
        date,
        flag,
        title,
        postings,
    })
}

fn parse_posting(document_id: &str, line: usize, raw_line: &str) -> Result<AstPosting, String> {
    let tokens = lex_line(raw_line.trim());
    let Some(account_token) = tokens.first() else {
        return Err("无法解析 posting".to_owned());
    };
    if account_token.token != SyntaxToken::Identifier {
        return Err("无法解析 posting".to_owned());
    }

    let amount = if tokens.len() >= 3
        && tokens[1].token == SyntaxToken::Number
        && tokens[2].token == SyntaxToken::Identifier
    {
        Some(AstAmount {
            value: tokens[1].slice.to_owned(),
            commodity: tokens[2].slice.to_owned(),
        })
    } else {
        None
    };

    Ok(AstPosting {
        span: span_for_line(document_id, line, raw_line),
        account: account_token.slice.to_owned(),
        amount,
    })
}

fn is_transaction_metadata_line(raw_line: &str) -> bool {
    let trimmed = raw_line.trim();

    for (index, ch) in trimmed.char_indices() {
        if ch != ':' {
            continue;
        }
        let key = &trimmed[..index];
        let rest = &trimmed[index + 1..];
        if key.is_empty() || key.chars().any(char::is_whitespace) {
            return false;
        }
        if rest.is_empty() || rest.chars().next().map_or(false, char::is_whitespace) {
            return true;
        }
    }

    false
}

fn unsupported_dated_directive_keyword(input: &str) -> Option<String> {
    let tokens = lex_line(input);
    match tokens.as_slice() {
        [LexedToken {
            token: SyntaxToken::Date,
            ..
        }, LexedToken {
            token: SyntaxToken::Identifier,
            slice: keyword,
            ..
        }, ..]
            if KNOWN_UNSUPPORTED_DATED_DIRECTIVES.contains(keyword) =>
        {
            Some((*keyword).to_owned())
        }
        _ => None,
    }
}

fn is_dated_directive(input: &str) -> bool {
    matches!(
        lex_line(input).first(),
        Some(LexedToken {
            token: SyntaxToken::Date,
            ..
        })
    )
}

fn is_open_directive(input: &str) -> bool {
    has_directive_token(input, SyntaxToken::Open)
}

fn is_close_directive(input: &str) -> bool {
    has_directive_token(input, SyntaxToken::Close)
}

fn is_price_directive(input: &str) -> bool {
    has_directive_token(input, SyntaxToken::Price)
}

fn is_balance_directive(input: &str) -> bool {
    has_directive_token(input, SyntaxToken::Balance)
}

fn has_directive_token(input: &str, expected: SyntaxToken) -> bool {
    let tokens = lex_line(input);
    matches!(
        tokens.as_slice(),
        [
            LexedToken {
                token: SyntaxToken::Date,
                ..
            },
            LexedToken { token, .. },
            ..,
        ] if *token == expected
    )
}

fn span_for_line(document_id: &str, line: usize, raw_line: &str) -> SourceSpan {
    let leading_trimmed = raw_line.trim_start();
    let column_start = raw_line.len().saturating_sub(leading_trimmed.len()) + 1;
    let column_end = raw_line.len().max(column_start);
    SourceSpan {
        document_id: document_id.to_owned(),
        line,
        column_start,
        column_end,
    }
}

fn unquote(value: &str) -> String {
    value.trim_matches('"').to_owned()
}

fn lex_line(input: &str) -> Vec<LexedToken<'_>> {
    let mut lexer = SyntaxToken::lexer(input);
    let mut tokens = Vec::new();
    while let Some(token) = lexer.next() {
        let Ok(token) = token else {
            continue;
        };
        tokens.push(LexedToken {
            token,
            slice: lexer.slice(),
        });
    }
    tokens
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct LexedToken<'a> {
    token: SyntaxToken,
    slice: &'a str,
}

#[derive(Logos, Clone, Copy, Debug, PartialEq, Eq)]
#[logos(skip r"[ \t]+")]
enum SyntaxToken {
    #[regex(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")]
    Date,
    #[token("include")]
    Include,
    #[token("open")]
    Open,
    #[token("close")]
    Close,
    #[token("price")]
    Price,
    #[token("balance")]
    Balance,
    #[token("*")]
    Star,
    #[token("!")]
    Bang,
    #[regex(r#""([^"\\]|\\.)*""#)]
    QuotedString,
    #[regex(r"[-+]?[0-9]+(?:\.[0-9]+)?")]
    Number,
    #[regex(r"[A-Za-z][A-Za-z0-9:_/-]*")]
    Identifier,
}
