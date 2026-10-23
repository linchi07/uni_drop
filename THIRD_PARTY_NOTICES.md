# Origin and notices

uni_drop was extracted from linchi07/uni_chat, specifically
app/lib/utils/paste_and_drop, on 2026-10-23. UniChat was not modified.
The most recent component commit at extraction was
38b9cfb1407692fe59a856571b687f9dfd2a493e (2026-03-21). tool/unichat_source_sha256.json records the SHA-256 of
every original component file. Only that component was extracted; the new
repository does not import the old application's Git history or other code.

The receiving render-object implementation originated in the Superlist native
extensions family and was adapted inside UniChat. Preserve the upstream MIT
notice in third_party_licenses/super-native-extensions-MIT.txt.
The runtime still depends on super_native_extensions and super_clipboard 0.9.1.

lib/src/file_semantic_map.g.dart was generated in UniChat from GitHub Linguist
language metadata. Its original generation script/version was not present in
the extracted component. Preserve the GitHub Linguist MIT notice in
third_party_licenses/github-linguist-MIT.txt. Its extension classifications are
best-effort metadata, not content validation. Explicit overrides correct the
known JSON ambiguity and common text formats.
