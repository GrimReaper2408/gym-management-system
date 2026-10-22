# Gym Management System

A small, beginner-friendly **DBMS college project**: a gym management web app built with
**MySQL 8**, **Python Flask**, **Jinja2 templates** and **Bootstrap 5**.

It manages members, plans, memberships, payments and attendance, and it demonstrates the
core DBMS syllabus topics: ER design, normalization, SQL, stored programs, and transactions.

> **Status of testing - please read**
> The code was written and checked in an environment that had **no MySQL server**, so
> the SQL scripts and the live database operations have **not been executed yet**.
> What *was* checked: Python syntax, Jinja template rendering and the form-validation / error-handling
> logic of every route (with the database layer replaced by a stub). See
> [section 9](#9-verification-status-and-how-to-test) for the exact test steps to run on your machine.

---

## 1. What is in the project

```
gym-management-system/
    app.py                  Flask backend (all routes, validation, DB access)
    requirements.txt        Python packages
    .env.example            Template for your database settings (copy to .env)
    .gitignore              Keeps .env and venv out of Git
    README.md               This file
    database/
        schema.sql          Creates the database + 5 tables
        seed.sql            Fictional sample data
        queries.sql         SQL syllabus examples (explained)
        stored_programs.sql Procedures, function, cursor, trigger + tests
        transactions.sql    Transactions, savepoints, locking demos
    templates/              Jinja2 pages (base, dashboard, members, plans, ...)
    static/style.css        Small CSS extras
    docs/
        ER_diagram.md       ER diagram (Mermaid), relational schema, keys
        normalization.md    Functional dependencies, 1NF/2NF/3NF
        DBMS_theory.md      MySQL vs PL/SQL, ACID, schedules, deadlocks, recovery
        viva_questions.md   25 questions with answers
```

### Features
- **Dashboard:** total members, active memberships, today's attendance, total payments.
- **Members:** add, view, edit, search (name / email / phone), safe delete.
- **Plans:** add, view, edit.
- **Memberships:** assign a plan to a member; the end date is calculated by the database.
- **Payments:** record and view.
- **Attendance:** record a check-in (today, now) and view the history.
- No login, charts, APIs, audit logs or trainer management (kept out on purpose).

---

## 2. MySQL is not Oracle PL/SQL

Many syllabi teach Oracle **PL/SQL**. MySQL does **not** understand PL/SQL. This project uses MySQL's own
stored programs, which provide the same ideas with different syntax:

| Idea | Oracle PL/SQL | MySQL (used here) |
|---|---|---|
| Procedure / function | `CREATE PROCEDURE ... IS` | `CREATE PROCEDURE ... BEGIN ... END` |
| Cursor | `CURSOR c IS ...` + `%NOTFOUND` | `DECLARE c CURSOR FOR ...` + `NOT FOUND` handler |
| Exceptions | `EXCEPTION WHEN ... THEN` | `DECLARE ... HANDLER FOR ...` |
| Raise an error | `RAISE_APPLICATION_ERROR` | `SIGNAL SQLSTATE '45000'` |
| Trigger values | `:NEW.col` | `NEW.col` |

Full comparison: [`docs/DBMS_theory.md`](docs/DBMS_theory.md), section 1.

---

## 3. Installation on Windows with VS Code

### 3.1 Install the tools (once)
1. **Python 3.10 or newer** from python.org. During setup tick **"Add python.exe to PATH"**.
2. **MySQL Server 8.0 or newer** (MySQL Installer for Windows). Remember the **root password** you choose.
   Make sure the `mysql` command works in a terminal. If it does not, add MySQL's `bin` folder
   (for example `C:\Program Files\MySQL\MySQL Server 8.0\bin`) to your PATH, or use the
   *MySQL 8.0 Command Line Client* from the Start menu instead (see the note in 3.3).
3. **VS Code** from code.visualstudio.com, with the **Python** extension.

### 3.2 Open the project and create a virtual environment
Open the `gym-management-system` folder in VS Code (**File > Open Folder**), then open a terminal
(**Terminal > New Terminal**) and run:

```powershell
python -m venv venv
venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If PowerShell says "running scripts is disabled", run this once and try again:
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
(or use Command Prompt and run `venv\Scripts\activate.bat` instead).

### 3.3 Create the database (exact SQL execution order)
Run the three scripts **in this order**. Each command asks for your MySQL root password.

```powershell
mysql -u root -p -e "source database/schema.sql"
mysql -u root -p -e "source database/seed.sql"
mysql -u root -p -e "source database/stored_programs.sql"
```

| Step | File | What it does |
|---|---|---|
| 1 | `schema.sql` | **Drops and re-creates** the `gym_management` database and its 5 tables |
| 2 | `seed.sql` | Inserts 3 plans, 10 members, 12 memberships, 11 payments, 12 attendance rows |
| 3 | `stored_programs.sql` | Creates the procedures, function, cursor procedure and trigger, then runs their tests |

Then, optionally, for your viva:

```powershell
mysql -u root -p -e "source database/queries.sql"
mysql -u root -p -e "source database/transactions.sql"
```

*Notes*
- Use forward slashes in `source database/schema.sql`. In PowerShell the `<` redirect operator does not work, which
  is why `-e "source ..."` is used. In Command Prompt, `mysql -u root -p < database\schema.sql` works too.
- Using the *MySQL Command Line Client* instead? Type `source C:/full/path/to/gym-management-system/database/schema.sql;`
  (and the same for the other files).
- MySQL Workbench also works: open each file and click the lightning-bolt button. Workbench understands
  `DELIMITER`.
- **The Flask app needs all three steps**, because it calls the stored procedures/function.
- Re-running `schema.sql` wipes the database; run steps 1-3 again to reset to the sample data.

### 3.4 Configure your database password
Copy the template and edit it:

```powershell
copy .env.example .env
```

Open `.env` in VS Code and set your real MySQL password:

```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_real_password
DB_NAME=gym_management
SECRET_KEY=any_random_text
```

`.env` is in `.gitignore`, so the password is never uploaded to GitHub. The password is **never** written in
the Python code.

### 3.5 Run the app

```powershell
python app.py
```

Open **http://127.0.0.1:5000** in your browser. Stop the server with `Ctrl+C`.
(Bootstrap is loaded from a CDN, so you need an internet connection for the styling.)

---

## 4. Syllabus mapping

Your college may number the units differently; match the **topic** to the file.

| Topic (typical unit) | Where it is in the project |
|---|---|
| Introduction to DBMS, ER model, keys, relationships | `docs/ER_diagram.md`, `database/schema.sql` |
| Relational model, constraints (PK, FK, UNIQUE, NOT NULL, CHECK) | `database/schema.sql`, `docs/ER_diagram.md` section 4-5 |
| SQL: DDL, DML, WHERE/LIKE/BETWEEN/IN/ORDER BY, joins, GROUP BY/HAVING, aggregates, subquery, UNION, string and date functions, view, index, EXPLAIN | `database/queries.sql` |
| Functional dependencies and normalization (1NF, 2NF, 3NF) | `docs/normalization.md` |
| Procedural SQL: procedures, functions, cursors, triggers, exception handling | `database/stored_programs.sql`, `docs/DBMS_theory.md` sections 1-3 |
| Transactions and ACID, COMMIT/ROLLBACK/SAVEPOINT | `database/transactions.sql` Parts 1-5, `docs/DBMS_theory.md` section 4 |
| Schedules, conflict serializability, precedence graph | `database/transactions.sql` Part 6, `docs/DBMS_theory.md` section 5 |
| Recoverable/cascadeless schedules, deadlocks, wait-die / wound-wait, log-based recovery, shadow paging | `docs/DBMS_theory.md` sections 6-8 |
| Locking and isolation in InnoDB (two sessions) | `database/transactions.sql` Part 7 |
| Database connectivity from an application | `app.py` |

---

## 5. SQL query explanations

Every query in [`database/queries.sql`](database/queries.sql) has a one- or two-sentence comment above it. Summary:

| Section | Topic | Example idea |
|---|---|---|
| 1 | CREATE, ALTER, INSERT, SELECT, UPDATE, DELETE | works on a throw-away copy table, then drops it |
| 2 | WHERE, LIKE, BETWEEN, IN, ORDER BY | recent members, names starting with A, payments in a range |
| 3 | INNER JOIN, LEFT JOIN | memberships with names; members who never bought a membership |
| 4 | COUNT, SUM, AVG, MIN, MAX | totals and averages |
| 5 | GROUP BY, HAVING | payments per method; returning members |
| 6 | Subquery | payments above the average |
| 7 | UNION, UNION ALL | the difference in duplicates |
| 8-9 | String and date functions | `CONCAT`, `SUBSTRING_INDEX`, `DATEDIFF`, `DATE_FORMAT` ... |
| 10-11 | EXPLAIN, VIEW, INDEX | before/after an index on `Attendance(attendance_date)` |

`queries.sql` never changes the real data. If you run it twice, drop the index first:
`DROP INDEX idx_attendance_date ON Attendance;`

## 6. Stored programs

Details are commented inside [`database/stored_programs.sql`](database/stored_programs.sql) and explained
in [`docs/DBMS_theory.md`](docs/DBMS_theory.md).

| Program | Used by the Flask app? |
|---|---|
| `AddMember` (procedure) | Yes: "Add member" form |
| `AssignMembership` (procedure) | Yes: "Assign" form on the Memberships page |
| `GetMembershipStatus` (function) | Yes: status column and the dashboard's "Active memberships" |
| `ShowExpiringMemberships` (cursor) | No, SQL demo only: `CALL ShowExpiringMemberships();` |
| `AfterAttendanceInsert` (trigger) | Yes, automatically: each check-in raises the member's visit count |
| `AssignAndPay` (procedure, in `transactions.sql`) | No, SQL demo of atomicity |

Exception handling (handlers + `SIGNAL SQLSTATE '45000'`) is shown in `AddMember` and `AssignMembership`.
Constraints vs triggers: rules a constraint can express (CHECK, UNIQUE, FOREIGN KEY) are constraints; only the
counter update is a trigger, so no rule is implemented twice.

## 7. Code-quality choices
- All SQL in `app.py` is **parameterised** (`%s` placeholders).
- Credentials come from `.env`; `.env.example` holds placeholders only.
- All form input is **validated on the server** (length, format, number ranges, dates not in the future).
- Database errors are caught and shown as red messages (duplicate email, delete blocked by related rows, missing stored
  programs, MySQL not running, ...).
- One short connection per query: simple to read and explain (a real production app would use a connection pool).

## 8. Known simplifications (on purpose)
- No login and no CSRF protection (the brief excluded login). Do not expose this app to the internet.
- A membership's start date cannot be in the future, so a membership is always either *Active* or *Expired*.
- Check-in does not require an active membership.
- Editing a plan does not change end dates of memberships already created.
- Deleting attendance rows would not decrease `total_visits` (the app has no delete for attendance).

---

## 9. Verification status and how to test

### Already checked (no database needed)
- `app.py` compiles, and its imports resolve (the MySQL connector itself was replaced by a stand-in).
- Every page renders from its Jinja template, and every form route was exercised with a stubbed database layer
  (48 checks, all passing): validation messages, success redirects, the exact arguments passed to the stored
  procedures, HTML escaping, and the translation of MySQL error numbers (1062, 1451, 1452, 1644, 3819,
  connection errors) into friendly messages.
- The date arithmetic of `seed.sql` was simulated in Python for 800 different "today" values: the same six memberships
  are always Active, memberships 3 and 4 are always the ones expiring within 7 days, and the payment total is 51,500.
- The SQL files were checked only for balanced parentheses and `BEGIN`/`END` blocks, which is **not** the same as running them.

### NOT yet verified (needs MySQL on your machine)
Nothing below has been run, so treat it as untested until you try it:
all five SQL scripts, the stored programs, and the real database reads/writes from Flask.

### Test checklist

**A. SQL scripts** (after running steps 1-3 above)

| Check | Expected |
|---|---|
| End of `seed.sql` output | `3, 10, 12, 11, 12` for plans, members, memberships, payments, attendance |
| `stored_programs.sql` Test 1 | one new member, `total_visits = 0` |
| Test 2 | quarterly membership, `end_date` = today + 3 months |
| Test 3 / 3b | `Active` for the new one; for the seed: Active for ids 1,2,3,4,5,8 and Expired for 6,7,9,10,11,12 |
| Test 4 | `total_visits` goes from 0 to 1 (trigger) |
| Test 5 | `ShowExpiringMemberships` lists memberships 3 and 4 |
| Test 6 (run one at a time) | errors 1644 "Email already registered", "Plan does not exist", "Member does not exist", and 1062 for a second check-in |
| `transactions.sql` Part 4 | failed call prints `FAILED: transaction rolled back...` and member 10 has 0 memberships; successful call prints `SUCCESS...` |
| `transactions.sql` last query | prices `1500.00`, `4000.00`, `14000.00` (data unchanged) |
| `queries.sql` | runs without errors (first time) |

**B. Web app** (after `python app.py`)

| Page | Action | Expected |
|---|---|---|
| Dashboard | open `/` | Members **10**, Active memberships **6**, Today's attendance **3**, Total payments **₹51,500.00** (with the untouched seed data) |
| Members | search `patel` | only Diya Patel |
| Members | add a member with an existing email | red "Email already registered" |
| Members | add a valid member | green message; new row; dashboard shows 11 members |
| Members | edit a member's phone | updated |
| Members | delete member #10 (Sneha Joshi, no records) | deleted |
| Members | delete member #1 | red "Cannot delete this member..." |
| Plans | add plan with price 0 or -5 | red validation message |
| Plans | edit Monthly price | updated |
| Memberships | assign Quarterly to a member starting today | green message with end date = today + 3 months; status Active |
| Payments | record a payment | row appears; dashboard total increases |
| Attendance | check in a member twice the same day | first: green; second: yellow "already checked in today" |
| Members | after a check-in | that member's **Visits** number is up by 1 (trigger) |

Please tell your teacher/yourself honestly which parts you ran. If something fails, the red message in the app
(and the terminal running `python app.py`) shows the MySQL error.

---

## 10. Troubleshooting

| Problem | Fix |
|---|---|
| "Cannot connect to the database" in the app | Start the MySQL service (Windows: Services > MySQL80), check `.env` (user, password, DB name), make sure step 1 was run |
| "A stored program is missing" | Run `stored_programs.sql` (step 3) |
| `'mysql' is not recognized` | Add MySQL's `bin` folder to PATH or use the MySQL Command Line Client |
| `ModuleNotFoundError: mysql` | Activate the venv and run `pip install -r requirements.txt` |
| `ERROR 1418 ... DETERMINISTIC` when creating the function | Ask your admin to enable `log_bin_trust_function_creators`, or run `SET GLOBAL log_bin_trust_function_creators = 1;` as root (the function is already declared `READS SQL DATA`, so this is rarely needed) |
| Access denied for user 'root' | Wrong password in `.env` |
| `CHECK` constraints seem ignored | You need MySQL **8.0.16 or newer** (older versions parse but ignore CHECK) |
