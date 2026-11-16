//! Small local-only JSON ABI shared by the native isolate and browser worker.
//! All offsets emitted by Harper are Unicode scalar offsets, never byte offsets.

use harper_core::{Dialect, Document, linting::{LintGroup, LintKind, Suggestion}, spell::FstDictionary};
use serde::{Deserialize, Serialize};
use std::cell::RefCell;

// Feature unification supplies secure browser randomness to both transitive
// getrandom major versions. The Wasm glue invokes the browser crypto API.
#[cfg(target_arch = "wasm32")]
use getrandom_02 as _;
#[cfg(target_arch = "wasm32")]
use getrandom_03 as _;

const MAX_REQUEST_BYTES: usize = 1_048_576;
const MAX_TEXT_SCALARS: usize = 32_768;
const MAX_FINDINGS: usize = 2_000;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    text: String,
    language: String,
    #[serde(default)]
    ignored_rules: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Finding {
    start: usize,
    end: usize,
    rule: String,
    category: String,
    message: String,
    replacements: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Response {
    status: String,
    offsets: String,
    findings: Vec<Finding>,
    message: Option<String>,
}

impl Response {
    fn error(status: &str, message: &str) -> Self {
        Self { status: status.into(), offsets: "unicode-scalar".into(), findings: vec![], message: Some(message.into()) }
    }
}

struct State {
    dialect: Dialect,
    linter: LintGroup,
}

thread_local! {
    static STATE: RefCell<Option<State>> = const { RefCell::new(None) };
    static OUTPUT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

fn run(input: &[u8]) -> Response {
    let request: Request = match serde_json::from_slice(input) {
        Ok(value) => value,
        Err(_) => return Response::error("failed", "Invalid Harper request JSON."),
    };
    let dialect = match request.language.as_str() {
        "en" | "en-US" => Dialect::American,
        "en-GB" => Dialect::British,
        "en-CA" => Dialect::Canadian,
        "en-AU" => Dialect::Australian,
        "en-IN" => Dialect::Indian,
        _ => return Response::error("unsupported", "Harper supports the configured English dialects only."),
    };
    if request.text.chars().count() > MAX_TEXT_SCALARS {
        return Response::error("failed", "Harper segment exceeds the 32768-character limit.");
    }
    let document = Document::new_plain_english_curated(&request.text);
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        if state.as_ref().is_none_or(|s| s.dialect != dialect) {
            *state = Some(State { dialect, linter: LintGroup::new_curated(FstDictionary::curated(), dialect) });
        }
        let state = state.as_mut().expect("initialized above");
        let mut findings = Vec::new();
        for (rule, lints) in state.linter.organized_lints(&document) {
            if request.ignored_rules.iter().any(|r| r == &rule || r == &format!("harper.{rule}")) { continue; }
            for lint in lints {
                if findings.len() == MAX_FINDINGS {
                    return Response::error("failed", "Harper exceeded the 2000-finding limit; split this segment.");
                }
                let source = lint.get_str(document.get_source());
                let replacements = lint.suggestions.iter().take(8).map(|suggestion| match suggestion {
                    Suggestion::ReplaceWith(chars) => chars.iter().collect::<String>(),
                    Suggestion::InsertAfter(chars) => source.clone() + &chars.iter().collect::<String>(),
                    Suggestion::Remove => String::new(),
                }).collect();
                let category = match lint.lint_kind {
                    LintKind::Spelling => "spelling",
                    LintKind::Enhancement | LintKind::Formatting | LintKind::Readability |
                    LintKind::Redundancy | LintKind::Regionalism | LintKind::Style => "style",
                    _ => "grammar",
                };
                findings.push(Finding {
                    start: lint.span.start, end: lint.span.end, rule: format!("harper.{rule}"),
                    category: category.into(), message: lint.message, replacements,
                });
            }
        }
        findings.sort_by(|a,b| (a.start,a.end,&a.rule).cmp(&(b.start,b.end,&b.rule)));
        Response { status: "success".into(), offsets: "unicode-scalar".into(), findings, message: None }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn quds_harper_abi_version() -> u32 { 1 }

/// Allocate an exact-sized buffer. The bridge must return it with the same size.
#[unsafe(no_mangle)]
pub extern "C" fn quds_harper_alloc(length: usize) -> *mut u8 {
    if length == 0 || length > MAX_REQUEST_BYTES { return std::ptr::null_mut(); }
    Box::into_raw(vec![0u8; length].into_boxed_slice()).cast::<u8>()
}

/// # Safety
/// `pointer` must be a live allocation returned by `quds_harper_alloc(length)`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn quds_harper_dealloc(pointer: *mut u8, length: usize) {
    if pointer.is_null() || length == 0 || length > MAX_REQUEST_BYTES { return; }
    unsafe { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, length))); }
}

/// The output remains valid on this thread until the next check. No caller frees it.
/// # Safety
/// `pointer` must reference `length` initialized bytes owned by the caller.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn quds_harper_check(pointer: *const u8, length: usize) -> *const u8 {
    let response = if pointer.is_null() || length == 0 || length > MAX_REQUEST_BYTES {
        Response::error("failed", "Invalid Harper input buffer.")
    } else {
        let input = unsafe { std::slice::from_raw_parts(pointer, length) };
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(input)))
            .unwrap_or_else(|_| Response::error("failed", "Harper could not check this text."))
    };
    OUTPUT.with(|output| {
        let mut output = output.borrow_mut();
        *output = serde_json::to_vec(&response).expect("Response serialization cannot fail");
        output.as_ptr()
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn quds_harper_result_len() -> usize {
    OUTPUT.with(|output| output.borrow().len())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(text: &str, language: &str) -> Response {
        run(serde_json::json!({"text":text,"language":language}).to_string().as_bytes())
    }

    #[test]
    fn real_grammar_and_replacement() {
        let out = check("This is an test.", "en-US");
        assert_eq!(out.status, "success");
        assert!(out.findings.iter().any(|f| f.rule == "harper.AnA" && f.replacements.iter().any(|r| r == "a")));
    }

    #[test]
    fn offsets_are_scalars_after_emoji() {
        let out = check("😀 This is an test.", "en-US");
        let finding = out.findings.iter().find(|f| f.rule == "harper.AnA").expect("article finding");
        assert_eq!((finding.start, finding.end), (10, 12));
        assert_eq!("😀 This is an test.".chars().skip(finding.start).take(finding.end-finding.start).collect::<String>(), "an");
    }

    #[test]
    fn unsupported_language_is_not_clean() {
        let out = check("Das ist korrekt.", "de-DE");
        assert_eq!(out.status, "unsupported");
    }

    #[test]
    fn ignored_rule_is_request_local() {
        let input = serde_json::json!({"text":"This is an test.","language":"en-US","ignored_rules":["harper.AnA"]});
        let out = run(input.to_string().as_bytes());
        assert!(!out.findings.iter().any(|f| f.rule == "harper.AnA"));
        assert!(check("This is an test.","en-US").findings.iter().any(|f| f.rule == "harper.AnA"));
    }

    #[test]
    fn rejects_invalid_input_and_limit() {
        assert_eq!(run(b"not json").status, "failed");
        assert_eq!(check(&"a".repeat(MAX_TEXT_SCALARS + 1), "en-US").status, "failed");
    }
}
