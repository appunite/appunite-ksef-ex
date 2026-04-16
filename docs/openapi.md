# OpenAPI Documentation Guide

Every REST API controller action **must** have an `open_api_spex` operation spec. This is NOT automatic — each action must be manually annotated.

---

## Setup

Add to the controller (if not already present):

```elixir
use OpenApiSpex.ControllerSpecs

alias KsefHubWeb.Schemas
alias OpenApiSpex.Schema

tags(["TagName"])
security([%{"bearer" => []}])
```

---

## Operation Spec Template

```elixir
operation(:index,
  summary: "Short summary",
  description: "Longer description of what this endpoint does.",
  parameters: [
    id: [in: :path, description: "Resource UUID.", schema: %Schema{type: :string, format: :uuid}],
    company_id: [in: :path, description: "Company UUID.", schema: %Schema{type: :string, format: :uuid}]
  ],
  request_body: {"Request body description", "application/json", Schemas.SomeRequest},
  responses: %{
    200 => {"Success", "application/json", Schemas.SomeResponse},
    401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
    404 => {"Not found", "application/json", Schemas.ErrorResponse}
  }
)

def index(conn, params) do
  # ...
end
```

`request_body` is only needed for `POST`/`PUT`/`PATCH` actions.

---

## Checklist for a new endpoint

1. Add `use OpenApiSpex.ControllerSpecs` to the controller
2. Define `operation(:action_name, ...)` above each action function
3. Create or reuse a schema in `lib/ksef_hub_web/schemas/` for request/response bodies
4. Verify it renders at `/dev/swaggerui` (run `mix phx.server` first)

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/ksef_hub_web/api_spec.ex` | Root OpenAPI spec — info, security schemes, servers |
| `lib/ksef_hub_web/schemas/` | Reusable request/response schemas |
| `GET /api/openapi` | Raw OpenAPI 3.0 JSON spec |
| `GET /dev/swaggerui` | Interactive SwaggerUI (dev only) |

---

## Common Response Schemas

Reuse these rather than defining inline:

| Schema | Used for |
|--------|---------|
| `Schemas.ErrorResponse` | 401, 403, 404, 422 error bodies |
| `Schemas.InvoiceResponse` | Single invoice response |
| `Schemas.InvoiceListResponse` | Paginated invoice list |

Check `lib/ksef_hub_web/schemas/` for the full list.
