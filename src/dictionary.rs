use std::collections::HashMap;

/// Apply word-level substitutions from `dict` to `text`.
///
/// Matching is case-insensitive and operates on whole tokens (split on
/// whitespace).  Leading/trailing punctuation is preserved around
/// substituted words.
pub fn apply(text: &str, dict: &HashMap<String, String>) -> String {
    if dict.is_empty() || text.is_empty() {
        return text.to_string();
    }

    // Lower-case keys once for fast lookup.
    let lower_dict: HashMap<String, &String> = dict
        .iter()
        .map(|(k, v)| (k.to_lowercase(), v))
        .collect();

    text.split_whitespace()
        .map(|token| {
            // Strip leading/trailing non-alphanumeric characters.
            let start = token
                .find(|c: char| c.is_alphanumeric())
                .unwrap_or(token.len());
            let end = token
                .rfind(|c: char| c.is_alphanumeric())
                .map(|i| i + token[i..].chars().next().map_or(1, |c| c.len_utf8()))
                .unwrap_or(0);

            if start >= end {
                return token.to_string();
            }

            let prefix = &token[..start];
            let core   = &token[start..end];
            let suffix = &token[end..];
            let key    = core.to_lowercase();

            if let Some(replacement) = lower_dict.get(&key) {
                format!("{prefix}{replacement}{suffix}")
            } else {
                token.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_substitution() {
        let mut d = HashMap::new();
        d.insert("gonna".into(), "going to".into());
        assert_eq!(apply("I'm gonna do it.", &d), "I'm going to do it.");
    }

    #[test]
    fn case_insensitive() {
        let mut d = HashMap::new();
        d.insert("hello".into(), "hi".into());
        assert_eq!(apply("Hello world", &d), "hi world");
    }

    #[test]
    fn empty_dict_passthrough() {
        let d = HashMap::new();
        let s = "unchanged text";
        assert_eq!(apply(s, &d), s);
    }
}
