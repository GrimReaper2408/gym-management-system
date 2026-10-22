"""
Gym Management System - Flask backend (DBMS college project)

How this file is organised
    1. Setup and database helpers   (connect to MySQL using values from .env)
    2. Input validation helpers     (server-side checks)
    3. Routes                       (one section per page)
    4. Start the app                (python app.py)

Rules followed throughout
    * Every SQL statement is parameterised (values go in the %s placeholders,
      never pasted into the SQL text), which prevents SQL injection.
    * Database errors are caught and shown as a red message instead of a crash.
    * Stored programs from database/stored_programs.sql are used where it makes
      sense: AddMember, AssignMembership and GetMembershipStatus.
"""

import os
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

import mysql.connector
from dotenv import load_dotenv
from flask import Flask, flash, redirect, render_template, request, url_for

# --------------------------------------------------------------------------
# 1. SETUP AND DATABASE HELPERS
# --------------------------------------------------------------------------

load_dotenv()  # reads the .env file (database password etc.) into environment variables

app = Flask(__name__)
# flash() messages need a secret key. If SECRET_KEY is not in .env we make a
# random one (messages still work; they only reset when the server restarts).
app.secret_key = os.getenv("SECRET_KEY") or os.urandom(24).hex()

PAYMENT_METHODS = ["Cash", "Card", "UPI"]  # must match the ENUM in schema.sql


def get_connection():
    """Open a new MySQL connection. Credentials come from .env, never from the code."""
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "gym_management"),
        charset="utf8mb4",
        collation="utf8mb4_unicode_ci",
    )


def query_all(sql, params=()):
    """Run a SELECT and return all rows as a list of dictionaries."""
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params)
        return cursor.fetchall()
    finally:
        conn.close()  # always close, even if the query failed


def query_one(sql, params=()):
    """Run a SELECT and return the first row (a dictionary) or None."""
    rows = query_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=()):
    """Run an INSERT / UPDATE / DELETE, save it (commit) and return the rows affected."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        conn.commit()
        return cursor.rowcount
    finally:
        conn.close()


def call_procedure(name, args):
    """Call a MySQL stored procedure and commit."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.callproc(name, args)
        conn.commit()
    finally:
        conn.close()


def friendly_error(err):
    """Turn a MySQL error into a short message a user can understand."""
    code = err.errno
    if code == 1644:   # raised by SIGNAL SQLSTATE '45000' in our stored procedures
        return err.msg
    if code == 1062:
        return "That value already exists and must be unique."
    if code == 1451:
        return "This record cannot be deleted because other records still depend on it."
    if code == 1452:
        return "The selected member, plan or membership does not exist."
    if code == 3819:
        return "A value was rejected by a database rule (for example a zero or negative amount)."
    if code in (2002, 2003, 1045, 1049):
        return ("Cannot connect to the database. Check that MySQL is running, that "
                "the settings in your .env file are correct, and that schema.sql was run.")
    if code in (1305, 1370):   # procedure/function does not exist, or not allowed to run
        return ("A stored program is missing. Run database/stored_programs.sql "
                "(see README, step 4).")
    return f"Database error: {err.msg}"


@app.template_filter("inr")
def inr(value):
    """Jinja filter: show a number as rupees, e.g. 1500 -> ₹1,500.00."""
    return f"₹{Decimal(value):,.2f}"


# --------------------------------------------------------------------------
# 2. INPUT VALIDATION HELPERS (the server never trusts the browser)
# --------------------------------------------------------------------------

EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_PATTERN = re.compile(r"^\d{10}$")


def parse_date(text):
    """Convert 'YYYY-MM-DD' text into a date, or return None if it is not valid."""
    try:
        result = datetime.strptime(text or "", "%Y-%m-%d").date()
    except ValueError:
        return None
    return result if result.year >= 1900 else None   # reject silly dates like 0001-01-01


def parse_int(text):
    """Convert text to a whole number, or return None."""
    try:
        return int(text)
    except (TypeError, ValueError):
        return None


def parse_money(text):
    """Convert text to a Decimal with 2 places, or return None if it is not a valid amount."""
    try:
        value = Decimal((text or "").strip())
    except InvalidOperation:
        return None
    if not value.is_finite():
        return None
    return value.quantize(Decimal("0.01"))


def validate_member(form):
    """Check the member form. Returns (clean_values, list_of_error_messages)."""
    errors = []
    name = form.get("name", "").strip()
    phone = form.get("phone", "").strip()
    email = form.get("email", "").strip().lower()
    join_date = parse_date(form.get("join_date", "").strip())

    if not 2 <= len(name) <= 100:
        errors.append("Name must be 2 to 100 characters.")
    if not PHONE_PATTERN.match(phone):
        errors.append("Phone must be exactly 10 digits.")
    if len(email) > 100 or not EMAIL_PATTERN.match(email):
        errors.append("Enter a valid email address (max 100 characters).")
    if join_date is None:
        errors.append("Join date is required (format YYYY-MM-DD).")
    elif join_date > date.today():
        errors.append("Join date cannot be in the future.")

    return {"name": name, "phone": phone, "email": email, "join_date": join_date}, errors


def validate_plan(form):
    """Check the plan form. Returns (clean_values, list_of_error_messages)."""
    errors = []
    plan_name = form.get("plan_name", "").strip()
    months = parse_int(form.get("duration_months", "").strip())
    price = parse_money(form.get("price", ""))

    if not 1 <= len(plan_name) <= 50:
        errors.append("Plan name must be 1 to 50 characters.")
    if months is None or not 1 <= months <= 60:
        errors.append("Duration must be a whole number of months between 1 and 60.")
    if price is None or price <= 0:
        errors.append("Price must be a number greater than zero.")
    elif price > Decimal("99999999.99"):
        errors.append("Price is too large.")

    return {"plan_name": plan_name, "duration_months": months, "price": price}, errors


# --------------------------------------------------------------------------
# 3. ROUTES
# --------------------------------------------------------------------------

# ---------- Dashboard ----------
@app.route("/")
def dashboard():
    stats = {"members": 0, "active": 0, "today": 0, "payments": Decimal("0")}
    try:
        stats["members"] = query_one("SELECT COUNT(*) AS n FROM Members")["n"]
        # GetMembershipStatus is our stored function: one definition of "active"
        # shared by the whole project.
        stats["active"] = query_one(
            "SELECT COUNT(*) AS n FROM Memberships "
            "WHERE GetMembershipStatus(membership_id) = 'Active'")["n"]
        stats["today"] = query_one(
            "SELECT COUNT(*) AS n FROM Attendance WHERE attendance_date = CURDATE()")["n"]
        stats["payments"] = query_one(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM Payments")["total"]
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return render_template("dashboard.html", stats=stats)


# ---------- Members ----------
@app.route("/members")
def members():
    search = request.args.get("q", "").strip()
    rows = []
    try:
        if search:
            like = f"%{search}%"  # % = wildcard; the value is still passed as a parameter
            rows = query_all(
                "SELECT member_id, name, phone, email, join_date, total_visits "
                "FROM Members WHERE name LIKE %s OR email LIKE %s OR phone LIKE %s "
                "ORDER BY member_id", (like, like, like))
        else:
            rows = query_all(
                "SELECT member_id, name, phone, email, join_date, total_visits "
                "FROM Members ORDER BY member_id")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return render_template("members.html", members=rows, search=search)


@app.route("/members/add", methods=["GET", "POST"])
def add_member():
    form = {"name": "", "phone": "", "email": "", "join_date": date.today().isoformat()}
    if request.method == "POST":
        values, errors = validate_member(request.form)
        form = {k: request.form.get(k, "") for k in form}  # keep what the user typed
        if errors:
            for message in errors:
                flash(message, "danger")
        else:
            try:
                # Stored procedure AddMember (handles the duplicate-email error itself)
                call_procedure("AddMember", (values["name"], values["phone"],
                                             values["email"], values["join_date"]))
                flash(f"Member '{values['name']}' was added.", "success")
                return redirect(url_for("members"))
            except mysql.connector.Error as err:
                flash(friendly_error(err), "danger")
    return render_template("member_form.html", form=form, member_id=None)


@app.route("/members/<int:member_id>/edit", methods=["GET", "POST"])
def edit_member(member_id):
    try:
        member = query_one("SELECT * FROM Members WHERE member_id = %s", (member_id,))
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
        return redirect(url_for("members"))
    if member is None:
        flash("Member not found.", "warning")
        return redirect(url_for("members"))

    form = {"name": member["name"], "phone": member["phone"], "email": member["email"],
            "join_date": member["join_date"].isoformat()}
    if request.method == "POST":
        values, errors = validate_member(request.form)
        form = {k: request.form.get(k, "") for k in form}
        if errors:
            for message in errors:
                flash(message, "danger")
        else:
            try:
                execute("UPDATE Members SET name = %s, phone = %s, email = %s, join_date = %s "
                        "WHERE member_id = %s",
                        (values["name"], values["phone"], values["email"],
                         values["join_date"], member_id))
                flash("Member updated.", "success")
                return redirect(url_for("members"))
            except mysql.connector.Error as err:
                if err.errno == 1062:
                    flash("Another member already uses that email.", "danger")
                else:
                    flash(friendly_error(err), "danger")
    return render_template("member_form.html", form=form, member_id=member_id)


@app.route("/members/<int:member_id>/delete", methods=["POST"])
def delete_member(member_id):
    # "Safe" delete: the foreign keys use RESTRICT, so MySQL refuses to delete a
    # member who still has memberships or attendance rows (error 1451).
    try:
        deleted = execute("DELETE FROM Members WHERE member_id = %s", (member_id,))
        if deleted:
            flash("Member deleted.", "success")
        else:
            flash("Member not found.", "warning")
    except mysql.connector.Error as err:
        if err.errno == 1451:
            flash("Cannot delete this member: they still have memberships or "
                  "attendance records.", "danger")
        else:
            flash(friendly_error(err), "danger")
    return redirect(url_for("members"))


# ---------- Plans (list, add and edit all live on one page) ----------
def show_plans(form=None, edit_id=None):
    """Load all plans and draw plans.html. `form` pre-fills the add/edit form."""
    plan_rows = []
    try:
        plan_rows = query_all("SELECT plan_id, plan_name, duration_months, price "
                              "FROM Plans ORDER BY plan_id")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    if form is None:
        form = {"plan_name": "", "duration_months": "", "price": ""}
        if edit_id is not None:
            current = next((p for p in plan_rows if p["plan_id"] == edit_id), None)
            if current:
                form = {"plan_name": current["plan_name"],
                        "duration_months": current["duration_months"],
                        "price": current["price"]}
            else:
                flash("Plan not found.", "warning")
                edit_id = None
    return render_template("plans.html", plans=plan_rows, form=form, edit_id=edit_id)


@app.route("/plans")
def plans():
    return show_plans(edit_id=parse_int(request.args.get("edit")))


@app.route("/plans/add", methods=["POST"])
def add_plan():
    values, errors = validate_plan(request.form)
    if errors:
        for message in errors:
            flash(message, "danger")
        return show_plans(form=dict(request.form))
    try:
        execute("INSERT INTO Plans (plan_name, duration_months, price) VALUES (%s, %s, %s)",
                (values["plan_name"], values["duration_months"], values["price"]))
        flash(f"Plan '{values['plan_name']}' was added.", "success")
        return redirect(url_for("plans"))
    except mysql.connector.Error as err:
        if err.errno == 1062:
            flash("A plan with that name already exists.", "danger")
        else:
            flash(friendly_error(err), "danger")
        return show_plans(form=dict(request.form))


@app.route("/plans/<int:plan_id>/edit", methods=["POST"])
def edit_plan(plan_id):
    values, errors = validate_plan(request.form)
    if errors:
        for message in errors:
            flash(message, "danger")
        return show_plans(form=dict(request.form), edit_id=plan_id)
    try:
        execute("UPDATE Plans SET plan_name = %s, duration_months = %s, price = %s "
                "WHERE plan_id = %s",
                (values["plan_name"], values["duration_months"], values["price"], plan_id))
        flash("Plan updated. (Existing memberships keep their original end dates.)", "success")
        return redirect(url_for("plans"))
    except mysql.connector.Error as err:
        if err.errno == 1062:
            flash("Another plan already uses that name.", "danger")
        else:
            flash(friendly_error(err), "danger")
        return show_plans(form=dict(request.form), edit_id=plan_id)


# ---------- Memberships ----------
@app.route("/memberships")
def memberships():
    rows, members_list, plans_list = [], [], []
    try:
        members_list = query_all("SELECT member_id, name FROM Members ORDER BY name")
        plans_list = query_all("SELECT plan_id, plan_name, duration_months, price "
                               "FROM Plans ORDER BY plan_id")
        rows = query_all(
            "SELECT ms.membership_id, m.name AS member_name, p.plan_name, "
            "       ms.start_date, ms.end_date, "
            "       GetMembershipStatus(ms.membership_id) AS current_status "
            "FROM Memberships ms "
            "JOIN Members m ON m.member_id = ms.member_id "
            "JOIN Plans   p ON p.plan_id   = ms.plan_id "
            "ORDER BY ms.membership_id DESC")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return render_template("memberships.html", memberships=rows, members=members_list,
                           plans=plans_list, today=date.today().isoformat())


@app.route("/memberships/assign", methods=["POST"])
def assign_membership():
    member_id = parse_int(request.form.get("member_id"))
    plan_id = parse_int(request.form.get("plan_id"))
    start_date = parse_date(request.form.get("start_date", "").strip())

    errors = []
    if member_id is None:
        errors.append("Choose a member.")
    if plan_id is None:
        errors.append("Choose a plan.")
    if start_date is None:
        errors.append("Start date is required (format YYYY-MM-DD).")
    elif start_date > date.today():
        # Keeps the status logic simple: a membership is either Active or Expired.
        errors.append("Start date cannot be in the future.")
    if errors:
        for message in errors:
            flash(message, "danger")
        return redirect(url_for("memberships"))

    try:
        # Stored procedure AssignMembership calculates end_date = start + plan duration.
        call_procedure("AssignMembership", (member_id, plan_id, start_date))
        created = query_one("SELECT end_date FROM Memberships WHERE member_id = %s "
                            "ORDER BY membership_id DESC LIMIT 1", (member_id,))
        flash(f"Membership assigned. It ends on {created['end_date']}.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return redirect(url_for("memberships"))


# ---------- Payments ----------
@app.route("/payments")
def payments():
    rows, choices = [], []
    try:
        choices = query_all(
            "SELECT ms.membership_id, m.name AS member_name, p.plan_name, p.price, ms.start_date "
            "FROM Memberships ms "
            "JOIN Members m ON m.member_id = ms.member_id "
            "JOIN Plans   p ON p.plan_id   = ms.plan_id "
            "ORDER BY ms.membership_id DESC")
        rows = query_all(
            "SELECT pay.payment_id, m.name AS member_name, p.plan_name, "
            "       pay.amount, pay.payment_date, pay.payment_method "
            "FROM Payments pay "
            "JOIN Memberships ms ON ms.membership_id = pay.membership_id "
            "JOIN Members m      ON m.member_id = ms.member_id "
            "JOIN Plans p        ON p.plan_id = ms.plan_id "
            "ORDER BY pay.payment_date DESC, pay.payment_id DESC")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return render_template("payments.html", payments=rows, choices=choices,
                           methods=PAYMENT_METHODS, today=date.today().isoformat())


@app.route("/payments/add", methods=["POST"])
def add_payment():
    membership_id = parse_int(request.form.get("membership_id"))
    amount = parse_money(request.form.get("amount", ""))
    payment_date = parse_date(request.form.get("payment_date", "").strip())
    method = request.form.get("payment_method", "")

    errors = []
    if membership_id is None:
        errors.append("Choose a membership.")
    if amount is None or amount <= 0:
        errors.append("Amount must be a number greater than zero.")
    elif amount > Decimal("99999999.99"):
        errors.append("Amount is too large.")
    if payment_date is None:
        errors.append("Payment date is required (format YYYY-MM-DD).")
    elif payment_date > date.today():
        errors.append("Payment date cannot be in the future.")
    if method not in PAYMENT_METHODS:
        errors.append("Choose a payment method.")
    if errors:
        for message in errors:
            flash(message, "danger")
        return redirect(url_for("payments"))

    try:
        execute("INSERT INTO Payments (membership_id, amount, payment_date, payment_method) "
                "VALUES (%s, %s, %s, %s)", (membership_id, amount, payment_date, method))
        flash(f"Payment of ₹{amount:,.2f} recorded.", "success")
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return redirect(url_for("payments"))


# ---------- Attendance ----------
@app.route("/attendance")
def attendance():
    rows, members_list = [], []
    try:
        members_list = query_all("SELECT member_id, name FROM Members ORDER BY name")
        rows = query_all(
            "SELECT a.attendance_id, m.name AS member_name, a.attendance_date, "
            "       TIME_FORMAT(a.check_in_time, %s) AS check_in "
            "FROM Attendance a JOIN Members m ON m.member_id = a.member_id "
            "ORDER BY a.attendance_date DESC, a.check_in_time DESC LIMIT 100",
            ("%H:%i",))   # the time format is passed as a parameter too
    except mysql.connector.Error as err:
        flash(friendly_error(err), "danger")
    return render_template("attendance.html", attendance=rows, members=members_list)


@app.route("/attendance/check-in", methods=["POST"])
def check_in():
    member_id = parse_int(request.form.get("member_id"))
    if member_id is None:
        flash("Choose a member.", "danger")
        return redirect(url_for("attendance"))
    try:
        # Date and time come from MySQL itself. The trigger AfterAttendanceInsert
        # then adds 1 to Members.total_visits automatically.
        execute("INSERT INTO Attendance (member_id, attendance_date, check_in_time) "
                "VALUES (%s, CURDATE(), CURTIME())", (member_id,))
        flash("Check-in recorded.", "success")
    except mysql.connector.Error as err:
        if err.errno == 1062:   # UNIQUE (member_id, attendance_date)
            flash("This member has already checked in today.", "warning")
        else:
            flash(friendly_error(err), "danger")
    return redirect(url_for("attendance"))


# --------------------------------------------------------------------------
# 4. START THE APP
# --------------------------------------------------------------------------
if __name__ == "__main__":
    # debug=True reloads the server when you edit code and shows detailed errors.
    # Fine for a local college project; never use it on a public server.
    app.run(debug=True)
