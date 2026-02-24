---
name: Security Audit
description: Scan code for vulnerabilities and suggest fixes.
---

# Security Audit Skill

When performing a security audit:

1. Check for injection vulnerabilities (SQL, XSS, command injection, path traversal)
2. Review authentication and authorization logic for bypass opportunities
3. Scan for hardcoded secrets, API keys, tokens, and credentials
4. Verify input validation and sanitization on all user-facing inputs
5. Check dependency versions for known CVEs using package managers
6. Review file permissions, environment variable handling, and error messages for information leakage
7. Assess CORS configuration, CSP headers, and cookie security attributes
8. Check for insecure deserialization and prototype pollution

Provide severity ratings (Critical, High, Medium, Low) and actionable remediation steps for each finding.
