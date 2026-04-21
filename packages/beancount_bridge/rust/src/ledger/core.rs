use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;

use crate::api::{
    RustAmount, RustLedgerDiagnostic, RustLedgerDirective, RustLedgerDirectiveKind,
    RustLedgerSnapshot, RustPosting, RustTransactionFlag,
};

const KNOWN_NON_TRANSACTION_DIRECTIVES: &[&str] = &[
    "commodity",
    "pad",
    "note",
    "document",
    "event",
    "query",
    "custom",
];

static DATE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\d{4}-\d{2}-\d{2}").expect("valid date regex"));
static INCLUDE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"^include\s+"([^"]+)"$"#).expect("valid include regex"));
static OPEN_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^open\s+([A-Z][A-Za-z0-9:-]*)").expect("valid open regex"));
static CLOSE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^close\s+([A-Z][A-Za-z0-9:-]*)").expect("valid close regex"));
static PRICE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^price\s+(\S+)\s+([-+]?\d+(?:\.\d+)?)\s+(\S+)$").expect("valid price regex")
});
static BALANCE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^balance\s+([A-Z][A-Za-z0-9:-]*)\s+([-+]?\d+(?:\.\d+)?)\s+(\S+)$")
        .expect("valid balance regex")
});
static FLAG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^([*!])\s*(.*)$").expect("valid flag regex"));
static QUOTED_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#""([^"]*)""#).expect("valid quoted regex"));
static TITLE_OPTION_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^option\s+"title"\s+"((?:[^"\\]|\\.)*)"\s*(?:[;#].*)?$"#)
        .expect("valid title option regex")
});
static METADATA_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z][a-z0-9_-]*:").expect("valid metadata regex"));
static POSTING_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^([A-Z][A-Za-z0-9:-]*)(?:\s+([-+]?\d+(?:\.\d+)?)\s+(\S+))?.*$")
        .expect("valid posting regex")
});
static DIRECTIVE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^([a-z][a-z0-9_-]*)\b").expect("valid directive regex"));

pub(crate) fn parse_workspace(root_path: &str, entry_file_path: &str) -> RustLedgerSnapshot {
    let absolute_root = normalize_absolute(Path::new(root_path));
    let mut parser = ParserState::new(absolute_root);
    parser.parse_file(&normalize_absolute(Path::new(entry_file_path)));
    parser.finalize_validation();

    RustLedgerSnapshot {
        workspace_id: parser
            .absolute_root
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("workspace")
            .to_owned(),
        workspace_name: parser.workspace_name(),
        loaded_file_count: parser.loaded_file_count,
        directives: parser.directives,
        diagnostics: parser.diagnostics,
    }
}

struct ParserState {
    absolute_root: PathBuf,
    workspace_title: Option<String>,
    directives: Vec<RustLedgerDirective>,
    diagnostics: Vec<RustLedgerDiagnostic>,
    visited_files: HashSet<PathBuf>,
    include_stack: Vec<PathBuf>,
    account_lifecycles: HashMap<String, AccountLifecycle>,
    loaded_file_count: i32,
}

impl ParserState {
    fn new(absolute_root: PathBuf) -> Self {
        Self {
            absolute_root,
            workspace_title: None,
            directives: Vec::new(),
            diagnostics: Vec::new(),
            visited_files: HashSet::new(),
            include_stack: Vec::new(),
            account_lifecycles: HashMap::new(),
            loaded_file_count: 0,
        }
    }

    fn parse_file(&mut self, file_path: &Path) {
        if !self.is_inside_root(file_path) {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "include 超出工作区根目录限制".to_owned(),
                location: file_path.display().to_string(),
                blocking: true,
            });
            return;
        }

        if self.include_stack.iter().any(|item| item == file_path) {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "检测到 include 循环".to_owned(),
                location: self.source_location(file_path, 1),
                blocking: true,
            });
            return;
        }

        if self.visited_files.contains(file_path) {
            return;
        }

        let contents = match fs::read_to_string(file_path) {
            Ok(contents) => contents,
            Err(_) => {
                self.diagnostics.push(RustLedgerDiagnostic {
                    message: "include 文件不存在".to_owned(),
                    location: file_path.display().to_string(),
                    blocking: true,
                });
                return;
            }
        };

        self.visited_files.insert(file_path.to_path_buf());
        self.include_stack.push(file_path.to_path_buf());
        self.loaded_file_count += 1;

        let lines = contents.lines().map(str::to_owned).collect::<Vec<_>>();
        let mut index = 0usize;
        while index < lines.len() {
            let raw_line = &lines[index];
            let trimmed = raw_line.trim();
            if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.starts_with('#') {
                index += 1;
                continue;
            }

            self.capture_workspace_title(trimmed);

            if trimmed.starts_with("include ") {
                self.handle_include(file_path, index + 1, trimmed);
                index += 1;
                continue;
            }

            let Some(date_match) = DATE_RE.find(trimmed) else {
                index += 1;
                continue;
            };

            let date = date_match.as_str().to_owned();
            let remainder = trimmed[10..].trim_start();
            let location = self.source_location(file_path, index + 1);

            if remainder.starts_with("open ") {
                self.parse_open_directive(&date, remainder, &location);
                index += 1;
                continue;
            }

            if remainder.starts_with("close ") {
                self.parse_close_directive(&date, remainder, &location);
                index += 1;
                continue;
            }

            if remainder.starts_with("price ") {
                self.parse_price_directive(&date, remainder, &location);
                index += 1;
                continue;
            }

            if remainder.starts_with("balance ") {
                self.parse_balance_directive(&date, remainder, &location);
                index += 1;
                continue;
            }

            if let Some(keyword) = extract_directive_keyword(remainder) {
                self.diagnostics.push(RustLedgerDiagnostic {
                    message: format!("暂不支持 {keyword} 指令，已跳过"),
                    location,
                    blocking: false,
                });
                index += 1;
                continue;
            }

            let mut posting_lines = Vec::new();
            while index + 1 < lines.len()
                && (lines[index + 1].starts_with(' ') || lines[index + 1].starts_with('\t'))
            {
                index += 1;
                posting_lines.push(lines[index].clone());
            }
            self.parse_transaction_directive(&date, remainder, &posting_lines, &location);
            index += 1;
        }

        self.include_stack.pop();
    }

    fn handle_include(&mut self, parent_file_path: &Path, line_number: usize, trimmed_line: &str) {
        let Some(include_match) = INCLUDE_RE.captures(trimmed_line) else {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "无法解析 include 指令".to_owned(),
                location: self.source_location(parent_file_path, line_number),
                blocking: true,
            });
            return;
        };

        let include_path = include_match.get(1).unwrap().as_str();
        if include_path.contains('*') {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "暂不支持 include 通配符".to_owned(),
                location: self.source_location(parent_file_path, line_number),
                blocking: false,
            });
            return;
        }

        let resolved = normalize_absolute(
            &parent_file_path
                .parent()
                .unwrap_or(parent_file_path)
                .join(include_path),
        );
        self.parse_file(&resolved);
    }

    fn parse_open_directive(&mut self, date: &str, remainder: &str, source_location: &str) {
        let Some(captures) = OPEN_RE.captures(remainder) else {
            self.add_syntax_issue(source_location, "无法解析 open 指令");
            return;
        };

        let account = captures.get(1).unwrap().as_str().to_owned();
        let lifecycle = self.account_lifecycles.entry(account.clone()).or_default();
        if lifecycle.open_date.is_none() {
            lifecycle.open_date = Some(date.to_owned());
        }
        lifecycle.last_activity_date = Some(date.to_owned());

        self.directives.push(RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Open,
            date_iso8601: iso_date(date),
            source_location: source_location.to_owned(),
            account: Some(account),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: None,
            postings: Vec::new(),
        });
    }

    fn parse_close_directive(&mut self, date: &str, remainder: &str, source_location: &str) {
        let Some(captures) = CLOSE_RE.captures(remainder) else {
            self.add_syntax_issue(source_location, "无法解析 close 指令");
            return;
        };

        let account = captures.get(1).unwrap().as_str().to_owned();
        let lifecycle = self.account_lifecycles.entry(account.clone()).or_default();
        lifecycle.close_date = Some(date.to_owned());
        lifecycle.last_activity_date = Some(date.to_owned());

        self.directives.push(RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Close,
            date_iso8601: iso_date(date),
            source_location: source_location.to_owned(),
            account: Some(account),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: None,
            postings: Vec::new(),
        });
    }

    fn parse_price_directive(&mut self, date: &str, remainder: &str, source_location: &str) {
        let Some(captures) = PRICE_RE.captures(remainder) else {
            self.add_syntax_issue(source_location, "无法解析 price 指令");
            return;
        };

        let base_commodity = captures.get(1).unwrap().as_str().to_owned();
        let value_text = captures.get(2).unwrap().as_str();
        let quote_commodity = captures.get(3).unwrap().as_str().to_owned();

        self.directives.push(RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Price,
            date_iso8601: iso_date(date),
            source_location: source_location.to_owned(),
            account: None,
            title: None,
            base_commodity: Some(base_commodity),
            quote_commodity: Some(quote_commodity.clone()),
            amount: Some(RustAmount {
                value: value_text.parse::<f64>().unwrap_or_default(),
                commodity: quote_commodity,
                fraction_digits: fraction_digits(value_text),
            }),
            transaction_flag: None,
            postings: Vec::new(),
        });
    }

    fn parse_balance_directive(&mut self, date: &str, remainder: &str, source_location: &str) {
        let Some(captures) = BALANCE_RE.captures(remainder) else {
            self.add_syntax_issue(source_location, "无法解析 balance 指令");
            return;
        };

        let account = captures.get(1).unwrap().as_str().to_owned();
        let value_text = captures.get(2).unwrap().as_str();
        let commodity = captures.get(3).unwrap().as_str().to_owned();
        self.touch_account(&account, date);
        self.directives.push(RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Balance,
            date_iso8601: iso_date(date),
            source_location: source_location.to_owned(),
            account: Some(account),
            title: None,
            base_commodity: None,
            quote_commodity: None,
            amount: Some(RustAmount {
                value: value_text.parse::<f64>().unwrap_or_default(),
                commodity,
                fraction_digits: fraction_digits(value_text),
            }),
            transaction_flag: None,
            postings: Vec::new(),
        });
    }

    fn parse_transaction_directive(
        &mut self,
        date: &str,
        header: &str,
        posting_lines: &[String],
        source_location: &str,
    ) {
        let flag_match = FLAG_RE.captures(header);
        let raw_flag = flag_match
            .as_ref()
            .and_then(|captures| captures.get(1))
            .map(|value| value.as_str());
        let description = flag_match
            .as_ref()
            .and_then(|captures| captures.get(2))
            .map(|value| value.as_str().trim())
            .unwrap_or_else(|| header.trim());
        let quoted = QUOTED_RE
            .captures_iter(description)
            .filter_map(|captures| {
                captures
                    .get(1)
                    .map(|value| value.as_str().trim().to_owned())
            })
            .filter(|value| !value.is_empty())
            .collect::<Vec<_>>();
        let title = if quoted.len() >= 2 {
            quoted[1].clone()
        } else if let Some(first) = quoted.first() {
            first.clone()
        } else {
            description.to_owned()
        };

        let mut postings = Vec::new();
        for posting_line in posting_lines {
            let trimmed = posting_line.trim();
            if trimmed.is_empty() || trimmed.starts_with(';') || METADATA_RE.is_match(trimmed) {
                continue;
            }

            let Some(captures) = POSTING_RE.captures(trimmed) else {
                self.add_syntax_issue(source_location, &format!("无法解析 posting: {trimmed}"));
                continue;
            };

            let account = captures.get(1).unwrap().as_str().to_owned();
            let amount = captures
                .get(2)
                .zip(captures.get(3))
                .map(|(value, commodity)| RustAmount {
                    value: value.as_str().parse::<f64>().unwrap_or_default(),
                    commodity: commodity.as_str().to_owned(),
                    fraction_digits: fraction_digits(value.as_str()),
                });
            postings.push(RustPosting {
                account: account.clone(),
                amount,
            });
            self.touch_account(&account, date);
        }

        if postings.len() < 2 {
            self.add_syntax_issue(source_location, "Transaction 至少需要两条 postings");
            return;
        }

        let postings = self.complete_postings_if_possible(postings, source_location);
        self.directives.push(RustLedgerDirective {
            kind: RustLedgerDirectiveKind::Transaction,
            date_iso8601: iso_date(date),
            source_location: source_location.to_owned(),
            account: None,
            title: Some(title),
            base_commodity: None,
            quote_commodity: None,
            amount: None,
            transaction_flag: Some(if raw_flag == Some("!") {
                RustTransactionFlag::Pending
            } else {
                RustTransactionFlag::Cleared
            }),
            postings,
        });
    }

    fn complete_postings_if_possible(
        &mut self,
        postings: Vec<RustPosting>,
        source_location: &str,
    ) -> Vec<RustPosting> {
        let missing_postings = postings
            .iter()
            .filter(|posting| posting.amount.is_none())
            .count();
        if missing_postings == 0 {
            self.validate_transaction_balance(&postings, source_location);
            return postings;
        }

        if missing_postings > 1 {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "暂不支持一笔交易中存在多条自动补平 postings".to_owned(),
                location: source_location.to_owned(),
                blocking: true,
            });
            return postings;
        }

        let mut explicit_totals = HashMap::<String, f64>::new();
        for posting in &postings {
            let Some(amount) = &posting.amount else {
                continue;
            };
            *explicit_totals.entry(amount.commodity.clone()).or_default() += amount.value;
        }

        if explicit_totals.len() != 1 {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "暂不支持多币种自动补平 transaction".to_owned(),
                location: source_location.to_owned(),
                blocking: true,
            });
            return postings;
        }

        let (commodity, total) = explicit_totals.into_iter().next().unwrap();
        let template = postings
            .iter()
            .find_map(|posting| posting.amount.clone())
            .expect("explicit total requires a posting amount");

        postings
            .into_iter()
            .map(|posting| {
                if posting.amount.is_some() {
                    posting
                } else {
                    RustPosting {
                        account: posting.account,
                        amount: Some(RustAmount {
                            value: -total,
                            commodity: commodity.clone(),
                            fraction_digits: template.fraction_digits,
                        }),
                    }
                }
            })
            .collect()
    }

    fn validate_transaction_balance(&mut self, postings: &[RustPosting], source_location: &str) {
        let mut totals = HashMap::<String, f64>::new();
        for posting in postings {
            let Some(amount) = &posting.amount else {
                continue;
            };
            *totals.entry(amount.commodity.clone()).or_default() += amount.value;
        }

        let is_balanced = totals.values().all(|value| value.abs() < 0.0000001);
        if !is_balanced {
            self.diagnostics.push(RustLedgerDiagnostic {
                message: "Transaction 不平衡".to_owned(),
                location: source_location.to_owned(),
                blocking: true,
            });
        }
    }

    fn finalize_validation(&mut self) {
        let directives = self.directives.clone();
        for directive in &directives {
            match directive.kind {
                RustLedgerDirectiveKind::Transaction => {
                    for posting in &directive.postings {
                        self.validate_account_usage(
                            &posting.account,
                            &directive.date_iso8601[..10],
                            &directive.source_location,
                        );
                    }
                }
                RustLedgerDirectiveKind::Balance => {
                    if let Some(account) = &directive.account {
                        self.validate_account_usage(
                            account,
                            &directive.date_iso8601[..10],
                            &directive.source_location,
                        );
                    }
                }
                RustLedgerDirectiveKind::Open
                | RustLedgerDirectiveKind::Close
                | RustLedgerDirectiveKind::Price => {}
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

    fn validate_account_usage(&mut self, account: &str, date: &str, source_location: &str) {
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

    fn touch_account(&mut self, account: &str, date: &str) {
        let lifecycle = self
            .account_lifecycles
            .entry(account.to_owned())
            .or_default();
        lifecycle.last_activity_date = Some(date.to_owned());
    }

    fn is_inside_root(&self, candidate_path: &Path) -> bool {
        candidate_path == self.absolute_root || candidate_path.starts_with(&self.absolute_root)
    }

    fn source_location(&self, file_path: &Path, line_number: usize) -> String {
        let relative = file_path
            .strip_prefix(&self.absolute_root)
            .ok()
            .map(|value| value.display().to_string())
            .unwrap_or_else(|| file_path.display().to_string());
        format!("{relative}:{line_number}")
    }

    fn add_syntax_issue(&mut self, source_location: &str, message: &str) {
        self.diagnostics.push(RustLedgerDiagnostic {
            message: message.to_owned(),
            location: source_location.to_owned(),
            blocking: true,
        });
    }

    fn capture_workspace_title(&mut self, trimmed_line: &str) {
        if self.workspace_title.is_some() {
            return;
        }
        let normalized_line = trimmed_line.trim_start_matches('\u{feff}');
        let Some(captures) = TITLE_OPTION_RE.captures(normalized_line) else {
            return;
        };
        let raw_title = captures
            .get(1)
            .map(|value| value.as_str())
            .unwrap_or_default();
        if raw_title.trim().is_empty() {
            return;
        }
        self.workspace_title = Some(raw_title.to_owned());
    }

    fn workspace_name(&self) -> String {
        if let Some(title) = self.workspace_title.as_ref().map(String::as_str) {
            return title.to_owned();
        }
        workspace_name_from_root(&self.absolute_root)
    }
}

#[derive(Default)]
struct AccountLifecycle {
    open_date: Option<String>,
    close_date: Option<String>,
    last_activity_date: Option<String>,
}

fn extract_directive_keyword(header: &str) -> Option<String> {
    let trimmed = header.trim_start();
    if trimmed.is_empty()
        || trimmed.starts_with('*')
        || trimmed.starts_with('!')
        || trimmed.starts_with('"')
    {
        return None;
    }

    let keyword = DIRECTIVE_RE
        .captures(trimmed)
        .and_then(|captures| captures.get(1))
        .map(|value| value.as_str().to_owned())?;
    KNOWN_NON_TRANSACTION_DIRECTIVES
        .contains(&keyword.as_str())
        .then_some(keyword)
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

fn workspace_name_from_root(root_path: &Path) -> String {
    root_path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("workspace")
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

fn normalize_absolute(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .expect("current directory")
            .join(path)
    };

    let mut normalized = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    normalized
}
