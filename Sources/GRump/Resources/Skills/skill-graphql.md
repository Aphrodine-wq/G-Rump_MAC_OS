---
name: GraphQL Design
description: Design GraphQL schemas, resolvers, and client integrations with best practices.
tags: [graphql, api, schema-design, resolvers, subscriptions]
---

# GraphQL Design

You are an expert at designing GraphQL APIs and schemas.

## Schema Design
- Use descriptive type names: `User`, `CreateUserInput`, `UserConnection`.
- Prefer object types over scalar fields for extensibility.
- Use interfaces for shared fields across types.
- Use unions for polymorphic return types.
- Always include `id: ID!` on entity types.
- Use `DateTime` scalar for timestamps, not String.

## Query Design
- Implement cursor-based pagination with Connection pattern (edges, nodes, pageInfo).
- Use `first`/`after` for forward pagination, `last`/`before` for backward.
- Keep queries shallow — avoid deeply nested resolvers (N+1 problem).
- Use DataLoader for batching and caching database queries.

## Mutations
- Use input types: `mutation createUser(input: CreateUserInput!): CreateUserPayload!`
- Return the modified object in the payload for cache updates.
- Include `userErrors` field in payloads for validation errors.
- Use optimistic responses on the client for instant UI feedback.

## Security
- Implement query depth limiting (max 10 levels).
- Implement query complexity analysis and cost limiting.
- Never expose internal IDs — use opaque cursors.
- Rate limit by query complexity, not just request count.
- Disable introspection in production.

## Subscriptions
- Use WebSocket transport (graphql-ws protocol).
- Keep subscription payloads minimal — client refetches full data.
- Implement heartbeat/keepalive for connection health.

## Anti-Patterns
- Exposing database schema directly as GraphQL schema
- Deeply nested queries without depth limiting (DoS vector)
- Mutations that don't return the modified object (forces client refetch)
- Using GraphQL for file uploads (use REST presigned URLs)
- N+1 resolver queries without DataLoader batching

## Verification
- Schema validates with `graphql-inspector` or similar tool
- Query depth and complexity limits are enforced
- All resolvers handle errors gracefully with structured error responses
- Introspection is disabled in production environments
