# Khatabook: Family Ledger and Field Service App

One mobile app with two uses:

1. **Family khatabook.** Personal and shared ledgers for family and friends. Who owes us, whom do we owe, all in one place, with a simple mode for elders.
2. **Business workspace** for the CCTV and solar business. Customers, job scheduling with automatic team notifications, materials used on the job, and an invoice ready to share with the customer on the spot. Unpaid invoices become customer udhaar in the business ledger automatically.

**Status:** Planning. No app code yet. Read the two documents below, answer the questions at the end of the product plan, and then we start building.

| Document | What it covers |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | Who uses the app, every feature, screens, step by step flows, build phases, decisions needed |
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | Tech stack, architecture, database design, security plan, notification engine, offline support, testing, costs |

## In one picture

```
                 +----------------------------------------+
                 |            Khatabook app               |
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
