# TCA ERP — Quickstart Guide (macOS)

An internal ERP for **Tunisie Conseil et Assistance (TCA)** — client/visa case management, accounting (invoices, treasury, banking), HR (requests, payroll), and a local AI assistant. Built with **React + Vite**, **FastAPI + SQLModel + PostgreSQL**, a local **Ollama** model (vision extraction + chat), and **LaTeX (TinyTeX)** for PDF generation.

---

## Features

- **Dashboard & Stats** — treasury net, bank reserves, client/invoice counts, visa-status breakdown, clients-by-country, factures-vs-reçus, payroll cost per period — all computed from live data, filterable by Tunisia / Libya.
  - **Custom charts** — each user can add their own charts on the Stats page (pick the data, what to group by, count or sum, bar / horizontal bar / line / pie, country, period). They're saved to the account (`stats_charts` table, computed by `backend/stats.py`) so the web and iOS apps show the same ones.
- **Clients** — add/edit/remove, AI passport extraction (OCR via Ollama vision model), manual client photo upload, arbitrary file attachments, visa status tracking.
- **Accounting** (per country: Tunisia / Libya)
  - **Invoices** — generate *factures* and *reçus* as real PDFs from your LaTeX templates (`backend/invoice_templates/`), download or remove.
  - **Treasury** — spending/gathering ledger, current-month totals (auto-resets each month since it's just filtered by date), historical monthly chart.
  - **Banking** — accounts, balances, transactions.
- **Human Resources**
  - **My Requests** — admin's own request log (name, description, status).
  - **Employee Requests** — vacations / salary advances / loans, submitted by any signed-in user; the submitter (or the admin) can remove a request.
  - **Fiche de paie** (Payroll) — upload the ZKTeco K40 time-clock export (.xls/.xlsx), enter the hourly rate and advances, and generate the Arabic « بطاقة خلاص الأجر » PDF (base, +25% overtime, +50% weekend, +100% holiday, daily detail) — same rules and layout as `paie_app.html`.
- **AI Chatbot** — a full assistant page (persists across navigation) and a small popup panel with a "Live helper" mode that attaches a snapshot of the current window to your question.
- **Role-based sidebar** — `Admin` sees everything; any other role sees Dashboard/Stats/Clients + Employee Requests + Chatbot only.
- **Authentication** — a single seeded Admin account; everyone else requests access, and the admin approves or rejects by email (or in-app under **Users**) before they can sign in.

---

## Prerequisites (macOS)

1. **Homebrew**
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
2. **Node.js** (v18+)AI Medical Chatbot using LLMs and RAG
   ```bash
   brew install node
   ```
3. **Python 3** (3.10+)
   ```bash
   brew install python
   ```
4. **PostgreSQL**
   ```bash
   brew install postgresql@16
   brew services start postgresql@16
   ```
5. **Ollama** (local LLM — vision extraction + chat)
   ```bash
   brew install ollama
   ollama serve   # or use the Ollama desktop app
   ollama pull qwen2.5vl:3b-8k
   ```
6. **TinyTeX** (LaTeX engine for invoice/payslip PDFs — no admin password needed, unlike MacTeX)
   ```bash
   curl -sL "https://yihui.org/tinytex/install-bin-unix.sh" | sh
   export PATH="$HOME/Library/TinyTeX/bin/universal-darwin:$PATH"   # add to your shell profile
   tlmgr install colortbl tikzfill collection-latexextra collection-pictures collection-langarabic collection-fontsextra
   ```
   The reçu template renders Arabic text with the Amiri font; its `.ttf` files already live in `backend/invoice_templates/` and are loaded by path, so no system font install is required.

---

## Installation

```bash
cd /path/to/zouhour
```

### 1. Frontend dependencies
```bash
npm install
```

### 2. Python virtual environment & backend dependencies
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Database
Create the app role and database once, as the `postgres` admin:
```bash
psql -U $(whoami) -h localhost -d postgres \
  -c "CREATE ROLE zouhour LOGIN PASSWORD 'your_app_password';" \
  -c "CREATE DATABASE zouhour OWNER zouhour;"
```

Copy `.env.example` to `.env` and put the app password in `DATABASE_URL`. Then create the tables:
```bash
.venv/bin/alembic upgrade head
```

After changing `backend/models.py`, create and apply a new migration:
```bash
.venv/bin/alembic revision --autogenerate -m "describe the change"
.venv/bin/alembic upgrade head
```

Backups:
```bash
pg_dump -U zouhour -h localhost zouhour > backup.sql
```

Client photos, other client files, generated invoice PDFs, and generated payslip PDFs are all saved under `uploads/` (git-ignored); the database stores only their paths.

**Everything the app persists lives in this one Postgres database** — clients, treasury entries, bank accounts/transactions, invoices, agency/employee requests, payslips, and now user accounts. There is no JSON file, mock data, or hardcoded fallback anywhere in the app anymore; if the API can't be reached, pages show an empty/error state instead of fake data.

### 4. Authentication secret & the one Admin account

Auth lives entirely in `backend/auth.py` (hashing, sessions, approval emails) and the `users` table (`backend/models.py`) — there is no `admin.json` anymore.

Add a signing secret to `.env` (this is what signs login sessions — treat it like a password):
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
# paste the output as JWT_SECRET= in .env
```

Also set in `.env`:
```
ADMIN_EMAIL=contact.ing.wissem@gmail.com   # change this to the real admin's email
APP_BASE_URL=http://localhost:5173
PUBLIC_API_BASE_URL=http://localhost:8001
```

Then create the one Admin account (prompts for a password, hidden input):
```bash
.venv/bin/python -m backend.seed_admin
```
Re-run it any time to change the admin's password. This is the **only** account created outside the normal signup flow.

**How signup works for everyone else:** they submit name/email/password on the login page → the account is created with `status = "pending"` → an email is sent to `ADMIN_EMAIL` with **Approve** / **Reject** links → clicking one activates or rejects the account. No SMTP configured yet? The email is printed to the backend console instead, so you can still click the link during local dev. The admin can also approve/reject from inside the app under **Users** (admin-only nav item) instead of using email.

**Configure outgoing email** (so the approval email actually gets delivered) by setting in `.env`:
```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-sending-address@gmail.com
SMTP_PASSWORD=an-app-password        # not your normal Gmail password — generate an App Password
SMTP_FROM=your-sending-address@gmail.com
```

---

## Working with the database

Day to day, you add/edit/remove data **through the app** — every screen is wired to a real endpoint that reads and writes Postgres. The steps below are for looking at the data directly or fixing something by hand.

### Connect with `psql` (already installed with Postgres)

```bash
psql -U zouhour -h localhost -d zouhour
```
It'll prompt for the password you set in `DATABASE_URL`. Useful commands once connected:

```sql
\dt                        -- list all tables
\d clients                 -- show a table's columns/types
SELECT * FROM clients;     -- view all rows
SELECT count(*) FROM invoices WHERE country = 'tunisia';
\q                         -- quit
```

To add or fix a row by hand (rare — prefer the UI):
```sql
UPDATE clients SET visa_status = 'approved' WHERE id = 3;
DELETE FROM treasury_entries WHERE id = 12;
INSERT INTO agency_requests (name, description, submitted_date, status)
  VALUES ('Renew license', 'Annual operating license renewal', '2026-10-01', 'pending');
```

### Prefer a GUI?

Any Postgres client works against the same `DATABASE_URL` (host `localhost`, port `5432`, db `zouhour`, user `zouhour`):
- **TablePlus** or **Postico** (macOS apps, free tier is enough) — browse/edit tables like a spreadsheet.
- **pgAdmin** (web-based, cross-platform).
- VS Code's **PostgreSQL** extension, if you'd rather stay in the editor.

### What's in each table

| Table | Holds |
|---|---|
| `clients` | Passport/visa case data, one row per client |
| `client_files` | Uploaded documents, linked to a client |
| `treasury_entries` | Spending/gathering ledger lines |
| `bank_accounts` | Bank accounts per country |
| `bank_transactions` | Deposits/withdrawals, linked to an account |
| `invoices` | Factures/reçus, with the line items stored as JSON in `items_json` |
| `agency_requests` | "My Requests" (admin's own log) |
| `employee_requests` | Vacations / salary advances / loans |
| `payslips` | Generated fiche de paie records |
| `users` | Login accounts — hashed passwords, role, and approval status |
| `alembic_version` | Internal — tracks which migration is applied. Don't edit. |

### Changing the schema

Never edit tables by hand to add a column — change `backend/models.py` instead, then generate and apply a migration (see the Database section above: `alembic revision --autogenerate` + `alembic upgrade head`). That keeps the Python models, the database, and everyone else's database in sync.

---

## Running the app

Four things need to be running at once:

| # | Service | Command | URL |
|---|---------|---------|-----|
| 1 | PostgreSQL | `brew services start postgresql@16` (if not already running) | `localhost:5432` |
| 2 | Ollama | `ollama serve` (skip if the desktop app is running) | `localhost:11434` |
| 3 | Backend (FastAPI) | `.venv/bin/python -m backend.backend` | `localhost:8001` (docs at `/docs`) |
| 4 | Frontend (Vite) | `npm run dev` | `localhost:5173` |

Open [http://localhost:5173](http://localhost:5173) and sign in with the admin account you created via `backend.seed_admin` (`role: "Admin"` unlocks Accounting, My Requests, Fiche de paie, and Users). Everyone else signs up and waits for approval.

---

## Configuration reference

- `.env` — `DATABASE_URL`, `JWT_SECRET`, `ADMIN_EMAIL`, `APP_BASE_URL`, `PUBLIC_API_BASE_URL`, `SMTP_*` (see Authentication above).
- `backend/auth.py` — password hashing, JWT session tokens, and the signup-approval email. Self-contained; nothing auth-related lives in `backend.py` itself beyond the route handlers.
- `backend/seed_admin.py` — creates/updates the one Admin account.
- `src/lib/config.js` — `CHAT_API_URL` (proxied to the backend's `/chat`).
- `backend/backend.py` — `CHAT_MODEL` constant (Ollama model used for the assistant and OCR extraction, default `qwen2.5vl:3b-8k`).
- `backend/invoice_templates/facture.tex` / `recu.tex` — the actual LaTeX source for generated invoices/receipts. Edit these to change the design; placeholders like `%%CLIENT_NAME%%` are substituted at generation time.
- `backend/payroll_template.tex` — LaTeX source for the payslip PDF.

---

## Troubleshooting

- **Port 8001 already in use**: `kill -9 $(lsof -t -i:8001)`
- **Port 5173 already in use**: `kill -9 $(lsof -t -i:5173)`
- **`DATABASE_URL` KeyError on backend start**: `.env` is missing or the backend wasn't started from the project root.
- **`pdflatex`/`xelatex: command not found` when generating a PDF**: TinyTeX isn't on the backend process's PATH. `backend/invoices.py` and `backend/payroll.py` auto-detect `~/Library/TinyTeX/bin/*`; if you installed it elsewhere, adjust `_tex_bin_dir()` in `backend/invoices.py`.
- **Invoice/payslip PDF fails with a LaTeX error**: run the same `pdflatex`/`xelatex` command by hand inside `uploads/invoices/<number>/` or `uploads/payslips/<number>/` to see the full log — the work directory and rendered `.tex` file are left in place.
- **Chat says it can't reach the assistant**: confirm `ollama serve` is running and `qwen2.5vl:3b-8k` is pulled (`ollama list`).
- **Backend not finding the app package**: always start it as `python -m backend.backend` (or `uvicorn backend.backend:app`) from the project root, never `cd backend && python backend.py`.
- **Backend refuses to start with a `JWT_SECRET is not set` error**: add it to `.env` (see Authentication above).
- **Signup approval email never arrives**: check the backend console — with no `SMTP_HOST` set, the approval email (including the Approve/Reject links) is printed there instead of sent.
- **"Not authenticated" (401) on every page**: your session expired (`JWT_EXPIRES_HOURS`, default 12h) or `.env`'s `JWT_SECRET` changed since you logged in — just log in again.

---

## Before deploying

- Set a real `JWT_SECRET`, `ADMIN_EMAIL`, and SMTP credentials in the production `.env` — don't reuse local dev values.
- Tighten CORS in `backend/backend.py` (currently `allow_origins=["*"]`) to your actual frontend domain.
- Serve everything over HTTPS — login/signup send passwords in plaintext-over-TLS; without TLS they're plaintext-over-nothing.
- Run `.venv/bin/python -m backend.seed_admin` once on the production database to create the real admin account, then keep that password somewhere safe (a password manager, not chat/notes).
