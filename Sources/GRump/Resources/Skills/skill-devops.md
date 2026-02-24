---
name: DevOps
description: CI/CD pipelines, Docker, and deployment configuration.
---

# DevOps Skill

When setting up DevOps workflows:

1. Write Dockerfiles with multi-stage builds, minimal base images, and non-root users
2. Use docker-compose for local development, Kubernetes for production
3. Set up CI/CD with GitHub Actions, GitLab CI, or similar: lint, test, build, deploy
4. Implement environment-specific configs via environment variables (12-factor app)
5. Add health check endpoints and readiness/liveness probes
6. Configure logging (structured JSON), monitoring (Prometheus/Grafana), and alerting
7. Use secrets management (Vault, AWS Secrets Manager, sealed secrets) instead of env files
8. Implement blue-green or canary deployments for zero-downtime releases
9. Automate rollback procedures and document disaster recovery steps

Infrastructure as Code: prefer Terraform or Pulumi over manual cloud console changes.
