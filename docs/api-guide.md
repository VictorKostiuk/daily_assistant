# Core API guide

JSON HTTP API at `/api/v1`. The machine-readable contract is [`openapi.yaml`](openapi.yaml).

What is and is not checked automatically:

- **Route parity runs in the suite.** `spec/openapi_surface_spec.rb` compares the live `/api/v1` (path, verb) surface to the document in both directions. It is an ordinary spec, so it runs wherever the suite runs — including the hosted `test` job, which invokes `bundle exec rspec`.
- **Schemas and examples are derived manually**, by reading the current controllers and request specs. Nothing verifies them against live responses.
- **Structural validation is performed separately, out of band**, with an external validator run by hand. Most recently `openapi-spec-validator` 0.7.1, against this file as it now stands:

  ```
  openapi-spec-validator --schema 3.0 docs/openapi.yaml
  docs/openapi.yaml: OK
  ```

  There is no validator dependency, rake task, or CI step in this repository, so structural validity is **not** continuously enforced; re-run it by hand after editing the file.

## Two kinds of client

The split is **transport**, not authentication. Google connect initiation is the only browser-originated, cross-origin operation. It still requires a bearer.

### 1. Server-to-server REST

Every `/api/v1` operation requires `Authorization: Bearer <token>` except these five:

- `POST /api/v1/auth/signup`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/password` (request a reset)
- `PUT /api/v1/auth/password` (complete a reset with a token)
- `OPTIONS /api/v1/integrations/google/connect` (CORS preflight)

`POST /api/v1/integrations/google/connect` is **not** in that list. A Devise session cookie is never accepted in place of a bearer. 401 `unauthorized` covers an absent, malformed, unknown, expired, or revoked token, and a user who is not `active`.

There is **no general cross-origin CORS support** for this API. That is not a ban on same-origin browser requests, and not a rule about how you build a non-browser client. Cross-origin browser access is enabled only for Google connect initiation, below.

### 2. Browser-originated Google connect

`POST /api/v1/integrations/google/connect` is different in **transport**: the consumer's browser calls it, including across a trusted sibling origin. It requires `Authorization: Bearer <token>`, and the browser must handle cookies (`credentials: include`).

**A fresh browser with no prior session can initiate.** This call issues the connection token and *writes* the connect intent into the session, so it **sets** the cookie on its own response. The requirement is not that the caller already holds a cookie — it is that the browser accepts the cookie this response sets and sends it back on the transport request and on the callback. The bearer binds the browser transaction to the API identity; the cookie carries the connect intent. Sending a cookie without the bearer is 401.

- Only **exact trusted sibling HTTPS origins** (plus same-origin and a missing `Origin`) are allowed. The allowlist is `GOOGLE_CONNECT_ORIGINS`. Any other origin is 403 `origin_not_allowed`.
- The browser must send `credentials: include`.
- `APP_URL` pins the OmniAuth callback and must be the same host that sets the session cookie.
- There is **no backend-forwarded-link flow**. A forwarded URL must never establish intent.

**Ordering is the security property:** the initiation `POST` establishes the intent, storing it through the existing Rails session mechanism rather than a second bespoke cookie. Opening the returned URL only validates that already-established binding — it never establishes it. The launch URL is reusable until the token is consumed or expires (15 minutes). The **token claim** is the single-use event, not the first open.

`OPTIONS /api/v1/integrations/google/connect` is the unauthenticated CORS preflight for that POST. It is not unconditional: a disallowed origin is 403 `origin_not_allowed`.

## Request and response shape

- Bodies are raw and flat. There is no root wrapper. `{"reminder":{...}}` to reminders is 422 `reminder is unknown`. `{"user":{...}}` to signup is 422 `email can't be blank` — unknown keys were dropped, so the nested fields were never read.
- Success bodies are bare objects. No `data` envelope. List endpoints have their own envelope (`items` plus a paging key).
- Every error the application renders uses `{"error":{"code","message","details"}}`. A malformed JSON body is a 422 envelope on the auth operations (`signup`, `login`, both `/api/v1/auth/password`) and a 400 elsewhere.
- A failure the application does **not** render — one that reaches Rails' public exception handler — does not use that envelope, and **its body depends on the request's `Accept` header**. Measured in a production-mode isolated copy on one such path (`GET /api/v1/calendar/events` with a `from` that matched the timestamp format but was out of range, before that path was corrected to 422):

  | `Accept` | Status | `content-type` | Body |
  | --- | --- | --- | --- |
  | `application/json` | 500 | `application/json` | `{"status":500,"error":"Internal Server Error"}` |
  | `text/html`, `*/*`, a browser `Accept` list, or no `Accept` header at all | 500 | `text/html` | the static `public/500.html` page |

  Do not code against a single shape here. That table was measured on that one path; other unhandled failures are not guaranteed to take the same renderer. Note in particular that `*/*` and an absent `Accept` both yield HTML, so a JSON client that does not send `Accept: application/json` will receive an HTML page.

Unknown **query** parameters are ignored on every operation.

Unknown **body** keys are not one rule:

| Operations | Unknown body key |
| --- | --- |
| Reminders, calendar events, AI messages, StudyWell settings/courses/obligations | 422 `validation_error` (`<key> is unknown`) |
| `signup` | Silently dropped (`params.permit`) |
| `login`, `POST`/`PUT /api/v1/auth/password` | Ignored (read listed keys only) |

`PUT /api/v1/reminders/{id}` is generated by Rails and is real, but it **does not replace** the resource. It merges, identical to `PATCH`. Omitted fields stay. Do not send a partial PUT expecting unspecified fields to reset.

`POST` and `PUT` on `/api/v1/auth/password` are two different operations: request a reset vs complete one with a token.

## Error codes

Eleven codes. Do not invent others.

| Code | HTTP | Typical cause |
| --- | --- | --- |
| `validation_error` | 422 | Invalid or unknown input |
| `unauthorized` | 401 | Missing/bad bearer, or user not `active` |
| `not_found` | 404 | No such resource for this caller |
| `conflict` | 409 | Reminder not in a changeable status; stale StudyWell `lock_version`; deleting a course that still has obligations |
| `integration_not_connected` | 409 | Google is not connected |
| `provider_error` | 502 | Upstream Google or OpenRouter failure |
| `local_save_failed` | 502 | Provider write succeeded; local row did not |
| `integration_unavailable` | 503 | Telegram/Google/OpenRouter unconfigured |
| `internal_error` | 500 | Unexpected failure |
| `too_many_requests` | 429 | Public credential throttle (see below) |
| `origin_not_allowed` | 403 | Google-connect origin not allowed |

`too_many_requests` is wired to three public endpoints, keyed by IP:

- `POST /api/v1/auth/login` — 10 per 3 minutes
- `POST /api/v1/auth/signup` — 5 per hour
- `POST /api/v1/auth/password` — 5 per hour

`PUT /api/v1/auth/password` is not throttled.

## Pagination

Four endpoints paginate. Do not conflate the keys. A client that treats a first page as the full set will lose rows.

| Endpoint | Query | Page size | Response key |
| --- | --- | --- | --- |
| `GET /api/v1/reminders` | `page` (positive integer, default 1) | 100 | `next_page` — integer or `null` |
| `GET /api/v1/studywell/courses` | `page` (positive integer, default 1) | 100 | `next_page` — integer or `null` |
| `GET /api/v1/studywell/courses/{course_id}/obligations` | `page` (positive integer, default 1) | 100 | `next_page` — integer or `null` |
| `GET /api/v1/calendar/events` | `page_token` (opaque) | Core requests `max_results: 100`; Google may return fewer | `next_page_token` |

A non-positive or non-integer `page` (including `?page=0` and `?page=abc`) is 422. A stale `page_token` that Google identifies as such is 422, not 502.

## Resource ids

Reminder, course, and obligation ids are local integer record ids. Calendar event ids are opaque Google event ids — not numeric, not client-generated.

## Timestamps

**Request body** (create/patch reminders and calendar events): date-only `YYYY-MM-DD` for all-day calendar events; ISO timestamps for timed values. An offset-free timestamp uses the caller's time zone. Timed calendar events require `end > start`. All-day events are inclusive and require `end >= start`. A calendar timing PATCH must send `starts_at`, `ends_at`, and `all_day` together.

**StudyWell obligation timestamps** (`due_at`, `starts_at`, `ends_at`) are a different rule: an explicit offset or `Z` is mandatory; a naive timestamp is 422. Course `active_from` / `active_until` are date-only `YYYY-MM-DD`.

**`from` / `to` query bounds** on `GET /api/v1/calendar/events` are a different rule: an explicit offset or `Z` is mandatory; a naive timestamp is 422. Both are required (blank → `can't be blank`). `from < to` is enforced.

## Source fields

`context_type` ∈ `life` / `study` / `work` / `global`, plus `source_app`, `source_entity_type`, `source_entity_id`. Semantics differ by operation:

| Operation | Omitted | Explicit `null` | Supplied |
| --- | --- | --- | --- |
| Resource PATCH / PUT (reminders, calendar) | Preserved | That field cleared | Only that field replaced |
| Resource create | Stores nothing | Stores nothing | Stored |
| AI messages (stateless) | Omitted from the response | Omitted, not echoed | Echoed |

Reminders and calendar events always emit all four keys (`null` when unset). The AI endpoint omits absent keys and also omits an explicit `null` — it does not echo `null`.

## AI

`POST /api/v1/ai/messages` is one-shot. No conversation, tools, or history endpoints exist. The model is server configuration: the response `model` reports what Core requested; `model` in the request body is 422.

No full prompt or answer is retained in `input_data` / `output_data` (both stay at the schema default `{}`). A bounded 120-character preview of the message **is** retained on the `ActionExecution` row for admin observation. `message` parameters are filtered from Rails request logs via `filter_parameters`. That is what is filtered and where; it is not a claim that every upstream or runtime log is free of sensitive content.

## HTML transports (not bearer REST)

These are not `/api/v1` operations and must not be called as JSON bearer endpoints.

- **Password recovery.** Request the reset through `POST /api/v1/auth/password`. The email links to `GET /auth/password/edit?reset_password_token=…`, a Core-hosted HTML form. Completing that form is `PUT /auth/password` (HTML). Completing via JSON is the separate public operation `PUT /api/v1/auth/password`.
- **Google OAuth.** After initiation, the browser opens `/auth/google_oauth2/connect?token=…`, then POSTs the CSRF-protected request phase and returns through `/auth/google_oauth2/callback`. Those routes authenticate nobody by bearer.
- **Staff UI.** `/` redirects to `/admin`. That surface is admin-only and uses Devise session login. Staff password recovery is still initiated through `POST /api/v1/auth/password` and completed through the HTML transport above.

## Tokens

Login issues a bearer token valid 30 days. Logout revokes only the presented token. Completing a password reset revokes outstanding API tokens and issues neither a session nor a new bearer.

On `POST /api/v1/auth/signup` and `PUT /api/v1/auth/password`, `password_confirmation` is not required. If it is supplied it must match `password`; if it is omitted there is no confirmation check.

A present, non-blank `time_zone` on signup must resolve via `ActiveSupport::TimeZone[]`. The judged value is the merged request parameter (query string overrides body), matching what is persisted. Invalid present values are 422 `details.time_zone`. A non-string value is 422, not treated as absent. Absent or blank is accepted and stored as submitted (blank is not normalised to null).

## StudyWell academic resources

All of these require a bearer token. Another user's id is 404, not 403. Collections use `{items, next_page}`, 100 records per page, positive integer `page` defaulting to 1, ascending id order. `next_page` is `null` only when the page is not truncated.

| Operation | Notes |
| --- | --- |
| `GET`/`PATCH /api/v1/studywell/settings` | `{time_zone, needs_time_zone_setup}`. Missing or unresolvable stored zone is reported as needing setup; UTC is not persisted on read. PATCH accepts only a valid named `time_zone`. |
| `GET`/`POST /api/v1/studywell/courses` | List owned courses / create. Default list excludes archived courses unless `include_archived=true` (exactly the strings `true` or `false`). |
| `GET`/`PATCH`/`DELETE /api/v1/studywell/courses/{id}` | PATCH includes boolean `archived`. DELETE is 409 with `details.obligations_count` while obligations exist; no cascade. |
| `GET`/`POST /api/v1/studywell/courses/{course_id}/obligations` | List/create within an owned course. `status=open\|done\|all`, default `all`. Creating inside an archived course is allowed. |
| `GET`/`PATCH`/`DELETE /api/v1/studywell/obligations/{id}` | PATCH cannot change `kind`. DELETE is explicit deletion, not completion. |

Course `name` and obligation `title` are rejected unless they contain at least one character outside `String#strip` (NUL and ASCII whitespace) **and** at least one character outside Unicode whitespace (`blank?`). The OpenAPI `pattern` encodes only the first conjunct; solely NBSP or ideographic space is still 422. Mixed NUL+NBSP is accepted.

Course and obligation PATCH and DELETE require integer `lock_version` in the JSON body, including `0` after create. Stale versions are 409 with no partial mutation. Omitted fields are preserved; explicit JSON `null` clears a nullable field. Wrong types and unknown body keys are 422 before filtering.

`remaining_minutes` is the rounded-up uncompleted fraction of `estimated_minutes`, only when both estimate and progress are known; otherwise `null`. Progress 100 does not complete work; `done` does not require progress 100. `archived_at` and `completed_at` are server-owned.

Obligation timestamps require an explicit offset or `Z`. Assignments take optional `due_at` and reject an interval. Exams reject `due_at` and take `starts_at`/`ends_at` both-absent-or-both-present. Study tasks may have both; a planned end must not be after `due_at`.

There is no `PUT` on StudyWell course or obligation routes.
