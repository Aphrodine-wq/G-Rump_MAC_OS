---
name: Docker & Container Deployment
description: Containerize applications and deploy with Docker, Compose, and orchestrators.
tags: [docker, containers, deployment, compose, registry, orchestration]
---

# Docker & Container Deployment Skill

When containerizing and deploying:

1. Write minimal Dockerfiles: use multi-stage builds to separate build and runtime layers
2. Use official base images and pin to specific tags (e.g., `node:20-alpine`, not `node:latest`)
3. Order Dockerfile instructions for optimal layer caching: dependencies first, source code last
4. Never store secrets in images — use build args sparingly, prefer runtime env vars or secret mounts
5. Add `.dockerignore` to exclude `.git`, `node_modules`, build artifacts, and sensitive files
6. Use health checks in Dockerfiles and Compose services (`HEALTHCHECK CMD`)
7. Run containers as non-root users (`USER node`, `USER appuser`)
8. Use Docker Compose for local multi-service development with shared networks and volumes
9. Tag images with git SHA or semantic version, not just `latest`
10. Scan images for vulnerabilities with `docker scout`, Trivy, or Snyk
11. Use resource limits (`--memory`, `--cpus`) to prevent runaway containers
12. For orchestration: prefer Kubernetes for production scale, Docker Swarm for simpler setups
13. Implement graceful shutdown: handle `SIGTERM` in your application to close connections cleanly
14. Use container registries (GHCR, ECR, Docker Hub) with access controls
15. Log to stdout/stderr — let the orchestrator handle log aggregation
