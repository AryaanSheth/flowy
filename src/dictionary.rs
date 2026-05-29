use std::collections::HashMap;

/// Apply whole-word, case-insensitive substitutions from `dict` to `text`.
///
/// Splits on whitespace.  Leading/trailing punctuation is preserved around
/// each substituted word.
pub fn apply(text: &str, dict: &HashMap<String, String>) -> String {
    if dict.is_empty() || text.is_empty() {
        return text.to_string();
    }

    // Lower-case the keys once for fast lookup.
    let ldict: HashMap<String, &String> =
        dict.iter().map(|(k, v)| (k.to_lowercase(), v)).collect();

    text.split_whitespace()
        .map(|token| substitute(token, &ldict))
        .collect::<Vec<_>>()
        .join(" ")
}

fn substitute(token: &str, dict: &HashMap<String, &String>) -> String {
    // Find the span of alphanumeric "core" characters.
    let start = token.find(|c: char| c.is_alphanumeric()).unwrap_or(token.len());
    if start >= token.len() {
        return token.to_string();
    }

    // Walk from the end to find the last alphanumeric character.
    let end = token
        .char_indices()
        .rev()
        .find(|(_, c)| c.is_alphanumeric())
        .map(|(i, c)| i + c.len_utf8()) // byte index AFTER the char
        .unwrap_or(0);

    if start >= end {
        return token.to_string();
    }

    let prefix = &token[..start];
    let core   = &token[start..end];
    let suffix = &token[end..];
    let key    = core.to_lowercase();

    if let Some(replacement) = dict.get(&key) {
        format!("{prefix}{replacement}{suffix}")
    } else {
        token.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dict(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn basic_substitution() {
        let d = dict(&[("gonna", "going to")]);
        assert_eq!(apply("I'm gonna do it.", &d), "I'm going to do it.");
    }

    #[test]
    fn case_insensitive() {
        let d = dict(&[("hello", "hi")]);
        assert_eq!(apply("Hello world", &d), "hi world");
    }

    #[test]
    fn preserves_punctuation() {
        let d = dict(&[("ok", "okay")]);
        assert_eq!(apply("Is that ok?", &d), "Is that okay?");
    }

    #[test]
    fn utf8_emoji_suffix() {
        let d = dict(&[("wow", "amazing")]);
        // emoji attached — substitution should not mangle the token
        let result = apply("wow! 🎉", &d);
        assert!(result.contains("amazing"));
    }

    #[test]
    fn empty_dict_passthrough() {
        let d = dict(&[]);
        let s = "unchanged text";
        assert_eq!(apply(s, &d), s);
    }
}
