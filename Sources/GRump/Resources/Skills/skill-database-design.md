---
name: Database Design
description: Schema design, migrations, and query optimization.
---

# Database Design Skill

When designing databases:

1. Normalize to 3NF by default; denormalize intentionally for read performance
2. Choose appropriate data types and add NOT NULL constraints where applicable
3. Add indexes for columns used in WHERE, JOIN, and ORDER BY clauses
4. Use foreign keys for referential integrity
5. Design migrations as reversible (up and down) and backwards-compatible
6. Use UUIDs or ULIDs for distributed systems; auto-increment for single-node
7. Add created_at and updated_at timestamps to all tables
8. Plan for soft deletes (deleted_at) when data retention is required
9. Write migrations that are safe for zero-downtime deploys (no table locks on large tables)

Always test migrations against a copy of production data before deploying.
