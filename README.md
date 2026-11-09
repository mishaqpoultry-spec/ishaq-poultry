# Shahzad Poultry Services — Supplier & Distribution Management

Owner contact: 0300-6388084

```
backend/   FastAPI + PostgreSQL + SQLAlchemy + Alembic
app/       Flutter (Android + Windows), Riverpod, Material 3
```

## One-time setup

### 1. Database (pgAdmin)
Create an empty database in pgAdmin (e.g. `shahzad_poultry`).

### 2. Backend config
```powershell
cd backend
copy .env.example .env
```
Edit `.env` and set the database name and postgres password:
```
DATABASE_URL=postgresql+psycopg://postgres:YOUR_PASSWORD@localhost:5432/YOUR_DB_NAME
JWT_SECRET=<any long random text>
```
If the password contains `@`, `#` or `%`, URL-encode it (`@` → `%40`, `#` → `%23`, `%` → `%25`).

### 3. Create tables and the owner login
```powershell
cd backend
.\.venv\Scripts\alembic.exe upgrade head
.\.venv\Scripts\python.exe -m app.cli create-admin shahzad "Shahzad"
```

## Daily run

Backend (keep this window open):
```powershell
cd backend
.\.venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000
```
API docs: http://localhost:8000/docs

App (from VS Code, or):
```powershell
cd app
flutter run -d windows
```
On a phone, open **Server settings** on the login screen and enter `http://<computer IP>:8000`.

## Tests
```powershell
cd backend; .\.venv\Scripts\python.exe -m pytest -q
# same tests on the real PostgreSQL DB (rolled back, leaves no data):
$env:PG_TEST="1"; .\.venv\Scripts\python.exe -m pytest -q; Remove-Item Env:PG_TEST
cd app;     flutter analyze; flutter test
```

## Phases
| Phase | Scope | Status |
|---|---|---|
| 1 | Setup, login/roles, audit log, Customers, Suppliers, logo | Done |
| 2 | Purchase / stock receiving, batches, inventory (birds and KG kept separate), losses, processing | Done |
| 3 | Daily supply + invoice flow: deliveries, rates (frozen on invoice), payment at delivery, invoice PDF, WhatsApp/SMS | Done |
| 4 | Statement PDF (any period: day / N days / week / month / year / custom), ledgers, returns, expenses | — |
| 5 | Dashboard stats, all reports, daily/stock PDFs, aging, profit and loss | — |
