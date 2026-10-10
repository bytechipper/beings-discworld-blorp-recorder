# Changelog

## 1.0.7

- Add `/blorps_clear` to clear the current character's saved list and stop recording, preserving other characters and the legacy list.

## 1.0.6

- Save blorps per logged-in character using Discworld GMCP identity.
- Clear active identity on disconnect and stop recording when switching characters.
- Preserve old shared lists with `/blorps_import_legacy` for explicit import.

## 1.0.5

- Validate against Mallard 0.27.0 (API 1.0).
- Add reproducible packaging and independent repository tests.
