---
name: Security Hygiene Checklist
description: Repository-level security audit checklist derived from OWASP Top 10 (2021) and common dependency/secret hygiene practices
version: 1
last_synced: 2026-04-19
sources:
  - url: https://owasp.org/Top10/2021/
    label: OWASP Top 10 — 2021
    last_fetched: 2026-04-19
  - url: https://cheatsheetseries.owasp.org/IndexTopTen.html
    label: OWASP Cheat Sheet Series — Top 10 index
    last_fetched: 2026-04-19
---

# Security Hygiene Checklist

Support file for the `gardener` skill's **Dependency & Security Hygiene** section (§4). This is a **repo-level** checklist — it catches configuration, dependency, and secret-handling issues that the gardener audit can observe without a deep code review. Anything that requires per-function threat analysis belongs to a dedicated `security-review` pass, not here.

For each item: **pass / fail / n/a** with evidence and a recommendation. Prioritize findings by **exploitability × blast radius**.

---

## 1. Secret & Credential Hygiene

- [ ] **No `.env` / `.envrc` / `credentials.json`** or similar credential files tracked in git (`git ls-files | grep -E '\\.env|credentials|secret'`).
- [ ] **No private keys or certificates** tracked in git (`*.pem`, `*.key`, `id_rsa`, `*.pfx`).
- [ ] **No API tokens, passwords, or connection strings** hard-coded in source (scan with `gitleaks`, `trufflehog`, or equivalent).
- [ ] **`.gitignore` covers** standard secret file patterns (`.env*`, `*.pem`, `*.key`, `secrets/`, `*.local.json`).
- [ ] **Git history is clean** — if a secret was ever committed, it has been rotated *and* removed from history (or documented as accepted risk).
- [ ] **Secret storage** for real secrets uses a proper mechanism (OS keychain, cloud secret manager, CI secret store), not checked-in files.
- [ ] **No `.DS_Store`, `Thumbs.db`, editor backup files, or IDE caches** tracked — they can leak paths and metadata.

## 2. Dependency & Supply Chain (OWASP A06, A08)

- [ ] **Manifests present** for the languages in use: `package.json`, `go.mod`, `pyproject.toml`/`requirements.txt`, `Cargo.toml`, `Gemfile`, etc.
- [ ] **Lockfiles committed** and in sync with manifests (`package-lock.json`/`pnpm-lock.yaml`/`yarn.lock`, `go.sum`, `poetry.lock`/`uv.lock`, `Cargo.lock`, `Gemfile.lock`).
- [ ] **Vulnerability scan** run with the ecosystem's native tool: `npm audit`, `pnpm audit`, `pip-audit`, `govulncheck`, `cargo audit`, `bundle audit`. Findings triaged.
- [ ] **Outdated dependencies** reviewed — major-version lag is intentional, not forgotten.
- [ ] **Third-party code integrity** — no random `curl | sh` pipes in build scripts without checksum verification; installed binaries are pinned.
- [ ] **Dependency count is justified** — large transitive dependency trees increase attack surface; flag suspicious / abandoned packages.
- [ ] **CI runs audits** on schedule or on every PR so drift is caught early.

## 3. Access Control & Authentication (OWASP A01, A07)

These are typically code-level concerns, but a few repo-level signals are worth checking:

- [ ] **Authentication logic isn't duplicated** across the codebase (a single auth module / middleware).
- [ ] **Authorization checks** are not inlined ad-hoc — they use a consistent pattern (middleware, decorator, policy object).
- [ ] **Password storage** (if applicable) uses a modern KDF (`argon2`, `bcrypt`, `scrypt`) — never plain/sha256/md5.
- [ ] **Session tokens** are stored/transmitted securely (httpOnly, Secure, SameSite cookies; short TTL + refresh).
- [ ] **MFA / 2FA** exists for sensitive accounts where the product model requires it.
- [ ] **Rate limiting** is in place on auth endpoints and other abuse-prone paths.

## 4. Cryptography (OWASP A02)

- [ ] **TLS enforced** on all external-facing endpoints; HSTS set where applicable.
- [ ] **No weak algorithms** — MD5, SHA-1, DES, 3DES, RC4 are not used for new security purposes (historical checksums aside).
- [ ] **Cryptographic primitives** use well-vetted libraries (`cryptography`, `libsodium`, language stdlib) — not hand-rolled.
- [ ] **Randomness** for security-sensitive values uses CSPRNGs (`crypto.randomBytes`, `secrets.token_*`, `/dev/urandom`), not `Math.random` / `rand()`.
- [ ] **Key rotation** and lifecycle are documented for any long-lived keys.

## 5. Injection & Input Handling (OWASP A03)

- [ ] **SQL access** uses parameterized queries or an ORM — no string concatenation into queries.
- [ ] **Shell invocations** use argv arrays (not string concatenation into `sh -c`), with input validated.
- [ ] **Template rendering** auto-escapes by default; raw/unescaped output is rare and justified.
- [ ] **JSON / XML parsers** are configured to reject unknown fields / external entities where relevant (XXE).
- [ ] **Content-Security-Policy** is set for web frontends; inline scripts are minimized or nonce'd.

## 6. Insecure Design & Misconfiguration (OWASP A04, A05)

- [ ] **Default passwords / admin accounts** are not shipped enabled.
- [ ] **Debug / dev endpoints** are disabled in production builds (and this is enforced, not just documented).
- [ ] **Error responses** don't leak stack traces, internal paths, or SQL in production.
- [ ] **CORS policy** is explicit and narrow (no wildcard origins with credentials).
- [ ] **HTTP security headers** are set: HSTS, X-Content-Type-Options, X-Frame-Options / frame-ancestors, Referrer-Policy.
- [ ] **File uploads** (if present) validate type, size, and path — no writes outside an upload dir.
- [ ] **Container images** use minimal base images, pinned by digest where possible; no `latest` tags in production.
- [ ] **IaC / deployment config** is in version control, reviewed, and scanned (tfsec, checkov, kube-linter).

## 7. Deserialization & Data Integrity (OWASP A08)

- [ ] **Deserialization of untrusted data** uses safe formats (JSON, protobuf) — not Python `pickle`, Java `ObjectInputStream`, Ruby `Marshal.load`, PHP `unserialize` on external input.
- [ ] **Subresource Integrity (SRI)** is used for third-party scripts loaded in web frontends.
- [ ] **Build pipeline** verifies signatures / checksums for downloaded artifacts.
- [ ] **Auto-updates** (if any) verify signatures before applying.

## 8. Logging & Monitoring (OWASP A09)

- [ ] **Security events logged**: failed auth, privilege changes, unusual access patterns.
- [ ] **Logs don't contain secrets** — tokens, passwords, and PII are redacted.
- [ ] **Log retention** is defined and honored (not indefinite for data with PII).
- [ ] **Alerting** exists on critical anomalies (if the project is production-serving).
- [ ] **Audit trail** for admin/destructive actions is non-repudiable.

## 9. SSRF & Outbound Request Safety (OWASP A10)

- [ ] **Outbound HTTP** from the server does not accept arbitrary user-supplied URLs without an allowlist.
- [ ] **Metadata endpoints** (`169.254.169.254`, cloud IMDS) are blocked at the network layer, or outbound requests use IMDSv2-only clients.
- [ ] **URL parsing** uses the standard library and is consistent across the codebase (avoid parser-differential vulnerabilities).

## 10. Repository & CI Hygiene

- [ ] **Branch protection** on the default branch (no direct pushes, required reviews).
- [ ] **CI secrets** are scoped (read-only where sufficient) and not exposed in pull_request workflows from forks.
- [ ] **Signed commits / signed tags** are used if the project's threat model justifies it.
- [ ] **Pre-commit hooks** include at least a secret scanner.
- [ ] **Pinned GitHub Actions** (by SHA or major version) — no floating refs for third-party actions.
- [ ] **Dependabot / Renovate** or equivalent is enabled and PRs are triaged.

---

## How to Use This Checklist

1. Cite this file from `SKILL.md` §4 — do not duplicate the content.
2. Walk sections in order. For each item produce: **status**, **evidence**, **recommendation**.
3. Distinguish **repo-observable** (can be checked with grep, ls, config inspection) from **needs-code-review** (requires understanding control flow). Flag the latter and escalate to a dedicated security review rather than guessing.
4. Prioritize findings: secret leaks and public-facing auth issues are **critical**; missing logging and hardening headers are **recommended**; style/convention is **info**.

## Scope Boundary

This checklist is intentionally coarse. Deep-dive code review — threat modeling, data flow analysis, specific CVE chains — belongs to a separate security-review pass. If a finding here surfaces *potential* but not *confirmed* vulnerability, log it as a prompt for follow-up, not as a verdict.

## Drift

Upstream OWASP guidance evolves (the 2025 Top 10 is in draft as of this writing). Run the gardener self-update workflow to resync this file against the sources in the frontmatter.
