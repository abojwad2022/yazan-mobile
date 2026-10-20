# YAZAN mobile workspace

Flutter/Dart workspace for the YAZAN Store and YAZAN Admin apps. Built and tested on GitHub Actions
(`.github/workflows/mobile.yml`); see `docs/mobile/03-ARCHITECTURE.md` for the server contract.

* `packages/domain` — pure Dart models (money, session, catalogue delta, errors).
* `packages/api_client` — Dio client: bearer, refresh-once, idempotency keys, ETag, byte counting.
* `packages/design_system` — YAZAN colours, theme, RTL-safe widgets.
* `packages/offline_sync` — outbox (idempotency key fixed per op), backoff, conflict handling, delta pull. Storage is an interface; the apps plug in encrypted SQLite.
