# Duebook: Family Ledger and Field Service App

One mobile app with two uses:

1. **Family khatabook.** Personal and shared ledgers for family and friends. Who owes us, whom do we owe, all in one place, with a simple mode for elders.
2. **Business workspace** for the CCTV and solar business. Customers, job scheduling with automatic team notifications, materials used on the job, and an invoice ready to share with the customer on the spot. Unpaid invoices become customer udhaar in the business ledger automatically.

**Status:** Phase 0 (foundation) in progress. Decisions are recorded in [docs/DECISIONS.md](docs/DECISIONS.md). The Flutter app lives in [app/](app/), the database in [supabase/](supabase/), and the build pipeline in [.github/workflows/](.github/workflows/).

| Document | What it covers |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | Who uses the app, every feature, screens, step by step flows, build phases, decisions needed |
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | Tech stack, architecture, database design, security plan, notification engine, offline support, testing, costs |
| [docs/SETUP_CHECKLIST.md](docs/SETUP_CHECKLIST.md) | Accounts, secrets and content the owner provides, and where each goes |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Decisions taken so far and placeholders still waiting on the owner |
| [docs/STEP_BY_STEP.md](docs/STEP_BY_STEP.md) | The owner's steps in order, with exactly what to send and where secrets go |
| [docs/S3_BACKUP_SETUP.md](docs/S3_BACKUP_SETUP.md) | Nightly backups to the owner's S3 bucket, with the exact IAM policy |

## In one picture

```
                 +----------------------------------------+
                 |             Duebook app                |
                 |  Personal  |   Family    |  Business   |
                 |   ledger   |   ledger    |  ledger +   |
                 |            |  + group    |  jobs +     |
                 |            |  dashboard  |  invoices   |
                 +------------------+---------------------+
                                    |
                     secure login, per row access rules
                                    |
                 +------------------v---------------------+
                 |  Supabase (Postgres, Auth, Storage,    |
                 |  Edge Functions, scheduled jobs)       |
                 +------------------+---------------------+
                                    |
                 +------------------v---------------------+
                 |  Firebase Cloud Messaging (push)       |
                 |  WhatsApp / SMS share sheet (invoices) |
                 +----------------------------------------+
```
