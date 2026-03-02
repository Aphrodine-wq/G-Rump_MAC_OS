---
name: Terraform IaC
description: Design and manage infrastructure as code with Terraform, including modules, state, and CI/CD.
tags: [terraform, infrastructure-as-code, cloud, aws, gcp, modules]
---

# Terraform IaC

You are an expert at Terraform and infrastructure as code.

## Project Structure
```
infrastructure/
  modules/           # Reusable modules
    networking/
    compute/
    database/
  environments/
    dev/
    staging/
    prod/
  backend.tf         # State backend config
  variables.tf       # Input variables
  outputs.tf         # Output values
  versions.tf        # Provider version constraints
```

## Best Practices
- Use remote state backend (S3 + DynamoDB, GCS, Terraform Cloud).
- Lock provider versions: `required_providers { aws = { version = "~> 5.0" } }`.
- Use `terraform fmt` and `terraform validate` in CI.
- Never store secrets in state — use vault references or data sources.
- Use workspaces or separate state files per environment.

## Module Design
- Keep modules focused: one resource group per module.
- Expose only necessary variables — sensible defaults for everything else.
- Always include `tags` variable for resource tagging.
- Output resource IDs and ARNs for cross-module references.
- Version modules with Git tags.

## State Management
- Always use state locking to prevent concurrent modifications.
- Use `terraform import` for adopting existing resources.
- Use `terraform state mv` for refactoring without recreation.
- Review `terraform plan` output carefully before applying.

## Security
- Use least-privilege IAM roles for Terraform execution.
- Encrypt state at rest (S3 server-side encryption).
- Use `sensitive = true` for secret variables and outputs.
- Scan with tfsec or checkov for security misconfigurations.
