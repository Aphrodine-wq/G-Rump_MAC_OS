---
name: Performance
description: Profile and optimize code performance.
---

# Performance Skill

When optimizing performance:

1. Identify the bottleneck before optimizing (measure, don't guess)
2. Profile CPU, memory, I/O, and network separately
3. Check algorithmic complexity: replace O(n^2) with O(n log n) or O(n) where possible
4. Optimize database queries: add indexes, reduce N+1 queries, use EXPLAIN
5. Implement caching at appropriate layers (memory, disk, CDN)
6. Reduce bundle sizes: tree-shake, code-split, lazy-load
7. Minimize allocations and GC pressure in hot paths
8. Use connection pooling, batch operations, and async I/O

Always benchmark before and after changes to verify improvement. Avoid premature optimization.
