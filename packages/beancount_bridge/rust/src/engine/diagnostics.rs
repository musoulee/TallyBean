#![allow(dead_code)]

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DiagnosticPhase {
    Syntax,
    Semantic,
}
