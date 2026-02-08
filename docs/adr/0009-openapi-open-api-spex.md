# 0009. OpenAPI Documentation with open_api_spex

Date: 2026-02-08

## Status

Accepted

## Context

The KSeF Hub REST API (invoices, tokens) is consumed by external applications. Without machine-readable documentation, consumers must rely on source code or ad-hoc documentation that drifts out of sync. We needed an OpenAPI 3.x spec that stays in sync with the codebase and provides an interactive explorer for developers.

## Decision

Use **open_api_spex** (`~> 3.22`) for OpenAPI 3.0 documentation of the REST API.

Each API controller action is annotated with an `operation(...)` macro from `OpenApiSpex.ControllerSpecs`. Reusable schemas live in `lib/ksef_hub_web/schemas/`. The spec is generated at runtime from these annotations via `KsefHubWeb.ApiSpec` and served as JSON at `GET /api/openapi`. A SwaggerUI is available in dev at `GET /dev/swaggerui`.

### Alternatives considered

| Option | Reason rejected |
|--------|----------------|
| **phoenix_swagger** | Targets Swagger 2.0 (not OpenAPI 3.x), less actively maintained, smaller community adoption. |
| **Hand-written OpenAPI YAML/JSON** | Drifts from code; no compile-time validation; duplicates effort. |
| **No API docs** | Unacceptable for external consumers; hinders onboarding and integration. |

## Consequences

- **Every new API endpoint must include an `operation(...)` spec.** This is documented in CLAUDE.md under "OpenAPI Documentation". Forgetting the annotation means the endpoint is invisible in the spec.
- **Schemas are defined separately from Ecto schemas.** The OpenAPI schemas in `lib/ksef_hub_web/schemas/` describe the JSON wire format, not the database structure. Changes to Ecto schemas may require corresponding updates to the OpenAPI schemas.
- **No request validation enabled yet.** open_api_spex supports automatic request casting/validation via `OpenApiSpex.Plug.CastAndValidate`, but we have not enabled it. Controllers continue to validate manually. This can be adopted incrementally.
- **No CI enforcement yet.** There is no CI step that verifies the spec is valid or complete. A future improvement could run `mix openapi.spec.json` and validate the output, or use `OpenApiSpex.TestAssertions` in controller tests to assert response schemas.
- **The `/api/openapi` endpoint is public** (no bearer token required) so that API consumers and tooling can fetch the spec without authentication.
- **SwaggerUI is dev-only** to avoid exposing an interactive API explorer in production.
