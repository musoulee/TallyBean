use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;

static INCLUDE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"^include\s+"([^"]+)"$"#).expect("valid include regex"));

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SourceDiagnostic {
    pub(crate) message: String,
    pub(crate) location: String,
    pub(crate) blocking: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct SourceSpan {
    pub(crate) document_id: String,
    pub(crate) line: usize,
    pub(crate) column_start: usize,
    pub(crate) column_end: usize,
}

#[derive(Clone, Debug)]
pub(crate) struct WorkspaceDocument {
    pub(crate) document_id: String,
    pub(crate) file_name: String,
    pub(crate) relative_path: String,
    #[allow(dead_code)]
    pub(crate) absolute_path: PathBuf,
    pub(crate) content: String,
    pub(crate) size_bytes: i32,
    pub(crate) is_entry: bool,
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub(crate) struct WorkspaceSourceSet {
    pub(crate) root_path: PathBuf,
    pub(crate) entry_document_id: String,
    pub(crate) documents: Vec<WorkspaceDocument>,
    pub(crate) diagnostics: Vec<SourceDiagnostic>,
}

pub(crate) fn load_workspace_source(
    root_path: &str,
    entry_file_path: &str,
) -> WorkspaceSourceSet {
    let absolute_root = normalize_absolute(Path::new(root_path));
    let absolute_entry = normalize_absolute(Path::new(entry_file_path));
    let entry_document_id = absolute_entry
        .strip_prefix(&absolute_root)
        .ok()
        .map(normalize_relative)
        .unwrap_or_else(|| absolute_entry.display().to_string());

    let mut loader = SourceLoader::new(absolute_root.clone(), absolute_entry.clone());
    loader.load_document(&absolute_entry);

    WorkspaceSourceSet {
        root_path: absolute_root,
        entry_document_id,
        documents: loader.documents,
        diagnostics: loader.diagnostics,
    }
}

struct SourceLoader {
    root_path: PathBuf,
    entry_path: PathBuf,
    documents: Vec<WorkspaceDocument>,
    diagnostics: Vec<SourceDiagnostic>,
    visited_documents: Vec<PathBuf>,
    include_stack: Vec<PathBuf>,
}

impl SourceLoader {
    fn new(root_path: PathBuf, entry_path: PathBuf) -> Self {
        Self {
            root_path,
            entry_path,
            documents: Vec::new(),
            diagnostics: Vec::new(),
            visited_documents: Vec::new(),
            include_stack: Vec::new(),
        }
    }

    fn load_document(&mut self, document_path: &Path) {
        if !self.is_inside_root(document_path) {
            self.diagnostics.push(SourceDiagnostic {
                message: "include 超出工作区根目录限制".to_owned(),
                location: document_path.display().to_string(),
                blocking: true,
            });
            return;
        }

        if self.include_stack.iter().any(|item| item == document_path) {
            self.diagnostics.push(SourceDiagnostic {
                message: "检测到 include 循环".to_owned(),
                location: self.source_location(document_path, 1),
                blocking: true,
            });
            return;
        }

        if self.visited_documents.iter().any(|item| item == document_path) {
            return;
        }

        let Ok(content) = fs::read_to_string(document_path) else {
            self.diagnostics.push(SourceDiagnostic {
                message: "include 文件不存在".to_owned(),
                location: document_path.display().to_string(),
                blocking: true,
            });
            return;
        };

        let Ok(relative_path) = document_path.strip_prefix(&self.root_path) else {
            return;
        };

        let relative_path = normalize_relative(relative_path);
        let file_name = document_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_owned();
        self.documents.push(WorkspaceDocument {
            document_id: relative_path.clone(),
            file_name,
            relative_path,
            absolute_path: document_path.to_path_buf(),
            size_bytes: content.len() as i32,
            content: content.clone(),
            is_entry: document_path == self.entry_path,
        });

        self.visited_documents.push(document_path.to_path_buf());
        self.include_stack.push(document_path.to_path_buf());

        for (index, raw_line) in content.lines().enumerate() {
            let trimmed = raw_line.trim();
            if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.starts_with('#') {
                continue;
            }

            let Some(include_match) = INCLUDE_RE.captures(trimmed) else {
                continue;
            };

            let include_path = include_match.get(1).unwrap().as_str();
            if include_path.contains('*') {
                self.diagnostics.push(SourceDiagnostic {
                    message: "暂不支持 include 通配符".to_owned(),
                    location: self.source_location(document_path, index + 1),
                    blocking: false,
                });
                continue;
            }

            let resolved = normalize_absolute(
                &document_path
                    .parent()
                    .unwrap_or(document_path)
                    .join(include_path),
            );
            self.load_document(&resolved);
        }

        self.include_stack.pop();
    }

    fn is_inside_root(&self, path: &Path) -> bool {
        path.starts_with(&self.root_path)
    }

    fn source_location(&self, file_path: &Path, line_number: usize) -> String {
        format!("{}:{line_number}", normalize_absolute(file_path).display())
    }
}

fn normalize_relative(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

pub(crate) fn normalize_absolute(path: &Path) -> PathBuf {
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
