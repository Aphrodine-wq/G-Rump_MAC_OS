---
name: API Design
description: Design RESTful and GraphQL APIs following best practices.
---

# API Design Skill

When designing APIs:

1. Use consistent resource naming (plural nouns, kebab-case)
2. Follow REST conventions: GET for reads, POST for creates, PUT/PATCH for updates, DELETE for deletes
3. Use proper HTTP status codes (201 Created, 204 No Content, 404 Not Found, 422 Unprocessable Entity)
4. Version APIs in the URL path (/v1/) or Accept header
5. Implement pagination for list endpoints (cursor-based preferred over offset)
6. Design idempotent operations where possible
7. Include rate limiting, authentication, and authorization from the start
8. Document with OpenAPI/Swagger: request/response schemas, examples, error formats
9. Use consistent error response format with code, message, and field-level details

For GraphQL: use relay-style pagination, input types for mutations, and descriptive field names.
