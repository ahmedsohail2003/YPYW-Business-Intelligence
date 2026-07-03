# Security & Privacy Self-Assessment — YPYW Business Intelligence Platform

A review of the security and privacy controls in this data platform, mapped to
**NIST CSF 2.0** functions, with an honest gap list.

> **Scope note:** a self-assessment of an educational data platform, not an
> audit. Implemented controls cite the code or template that enforces them.

## 1. Data privacy by design

The strongest control in this repository is a privacy decision, not a
technical one: the platform was developed against real business operations,
but **the repository contains only synthetic data**. `sample_estimates.csv`
uses generated names and amounts, and `azure/generate_sample_data.py` enriches
it with a fixed seed so the demo is reproducible without ever exposing a real
client record. The dashboard preview is rendered from that synthetic set and
is labeled as such. This is data minimization applied to a portfolio: the
public artifact demonstrates the system while containing zero real PII.

## 2. Control mapping — NIST CSF 2.0

| CSF function | Implemented | Evidence |
|---|---|---|
| **Govern (GV)** | Data-handling posture documented in the README ("Note on Data"); deployment runbook documents the security-relevant steps and cost/limit posture | `README.md`, `azure/DEPLOY.md` |
| **Identify (ID)** | All cloud resources declared as code (Bicep), so the asset inventory *is* the template: one logical server, one database, one firewall rule — nothing undocumented | `azure/main.bicep` |
| **Protect (PR)** | *Transport:* SQL server enforces `minimalTlsVersion: '1.2'`; the ETL connection string sets `Encrypt=yes; TrustServerCertificate=no` (encrypted, certificate actually validated). *Network:* firewall rule scoped to a single client IP (`startIpAddress == endIpAddress`) — least privilege rather than 0.0.0.0. *Secrets:* SQL admin password is never committed; read from `SQL_ADMIN_PASSWORD` at runtime, passed to Azure as a `@secure()` Bicep parameter, `.env` gitignored with a committed `.env.example`. *App:* Blazor pipeline enables HSTS and HTTPS redirection outside development | `main.bicep`, `dataingest.py get_engine()`, `deploy.ps1`, `CPA.Web/Program.cs` |
| **Detect (DE)** | CI runs the ETL test suite on every push (3.11/3.12 matrix); ETL failures are logged with full exception context rather than swallowed | `.github/workflows/ci.yml`, `dataingest.py process_data()` |
| **Respond (RS)** | Ingest failures are contained per-file: one bad CSV logs an exception and does not crash the watcher; the dashboard degrades to a clear "connect a database" banner instead of erroring when the backend is unavailable | `dataingest.py`, `Home.razor` |
| **Recover (RC)** | Idempotent-by-design rebuild path: `deploy.ps1` + `schema.sql` (every object guarded with `IF NOT EXISTS` / `CREATE OR ALTER`) can recreate the entire backend from scratch; processed source files are archived, not deleted, with collision-safe naming | `schema.sql`, `build_archive_path()` |

## 3. Gaps and remediations (prioritized)

| # | Gap | CSF ref | Remediation |
|---|---|---|---|
| G-1 | Application and ETL connect as the SQL **admin** account | PR.AA-05 (least privilege) | Create a contained database user with only the needed table/view permissions; reserve the admin login for deployment |
| G-2 | Password-based auth to Azure SQL | PR.AA | Move to Microsoft Entra authentication with a managed identity for the app; eliminates the standing secret entirely |
| G-3 | `publicNetworkAccess: 'Enabled'` on the SQL server (mitigated by the single-IP firewall) | PR.IR | Private endpoint or service endpoint; disable public network access |
| G-4 | No Azure SQL auditing / Advanced Threat Protection enabled | DE.CM | Enable server auditing to a Log Analytics workspace and Defender for SQL |
| G-5 | ETL trusts CSV headers/content after a whitespace strip only | PR.DS (input validation) | Schema validation on ingest (required columns, types, row-count sanity) with quarantining of rejected files |

## 4. References

- NIST Cybersecurity Framework 2.0 (NIST CSWP 29).
- Azure SQL security baseline concepts: TLS enforcement, firewall scoping,
  Entra/managed-identity authentication, auditing.
