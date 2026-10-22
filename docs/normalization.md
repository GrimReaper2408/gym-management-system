# Normalization

Normalization organises tables so each fact is stored once. This removes three kinds of
problems called **anomalies**:

- **Insert anomaly** - you cannot store a fact without storing an unrelated one.
- **Update anomaly** - the same fact is stored many times and one copy gets missed when it changes.
- **Delete anomaly** - deleting one fact accidentally deletes another.

## 1. Functional dependencies (FDs) in this project

`X -> Y` means "if you know X, you can find exactly one Y".

| Table | Functional dependencies |
|---|---|
| Members | `member_id -> name, phone, email, join_date, total_visits`; `email -> member_id` |
| Plans | `plan_id -> plan_name, duration_months, price`; `plan_name -> plan_id` |
| Memberships | `membership_id -> member_id, plan_id, start_date, end_date, status` |
| Payments | `payment_id -> membership_id, amount, payment_date, payment_method` |
| Attendance | `attendance_id -> member_id, attendance_date, check_in_time`; `(member_id, attendance_date) -> attendance_id, check_in_time` |

In every table the left side of each FD is a candidate key (the primary key, or a UNIQUE column),
apart from the two notes in section 5.

## 2. First Normal Form (1NF)

**Rule:** every column holds one single (atomic) value, and there are no repeating groups.

*Not in 1NF* - phone numbers stored as a list in one cell:

| member_id | name | phones |
|---|---|---|
| 1 | Aarav | 9876500001, 9123400001 |

*Fix:* one value per cell. In our project each member has one `phone` value, and anything
that repeats (memberships, payments, check-ins) lives in its own table with one row per event,
not in a list inside `Members`.

## 3. Second Normal Form (2NF)

**Rule:** the table is in 1NF and no non-key column depends on only *part* of a composite key.
(It only matters when the primary key has more than one column.)

*Not in 2NF* - a table with composite key `(member_id, plan_id)`:

| member_id | plan_id | plan_name | start_date |
|---|---|---|---|
| 1 | 3 | Annual | 2026-07-01 |

`plan_name` depends only on `plan_id` (part of the key), so the plan name is repeated for every
member who buys that plan.

*Fix:* move plan facts to `Plans(plan_id, plan_name, ...)` and keep only `plan_id` in the
bridge table. Our `Memberships` table avoids the problem completely by using a
single-column surrogate key `membership_id`.

## 4. Third Normal Form (3NF)

**Rule:** the table is in 2NF and no non-key column depends on another non-key column
(no *transitive dependency*: `key -> A -> B`).

*Not in 3NF* - plan details copied into Memberships:

| membership_id | member_id | plan_id | plan_name | price |
|---|---|---|---|---|
| 1 | 1 | 3 | Annual | 14000 |

Here `membership_id -> plan_id` and `plan_id -> price`, so `price` depends on the key only
*through* `plan_id`. Changing the Annual price would mean updating many rows.

*Fix (what we did):* `plan_name`, `duration_months` and `price` live only in `Plans`;
`Memberships` stores just `plan_id`. Likewise the member's name and email live only in `Members`.

## 5. Two deliberate exceptions (honest notes for the viva)

1. **`Memberships.end_date` is derived data.** It equals `start_date + Plans.duration_months`,
   so strictly it is a dependency between non-key attributes. We store it anyway because
   (a) the end date must not change if the plan's duration is edited later,
   (b) it makes "who is expiring soon?" queries simple and fast. The stored procedure
   `AssignMembership` is the single place that calculates it.
2. **`Members.total_visits` is a derived counter** (the number of rows in Attendance for that member).
   It is intentionally *denormalized* to demonstrate a trigger. The trigger
   `AfterAttendanceInsert` keeps it correct, and the seed script recalculates it from Attendance.
   It could always be recomputed with `SELECT COUNT(*) FROM Attendance WHERE member_id = ...`.

Apart from these two derived columns, every table is in 3NF (and BCNF, because every other determinant is a candidate key).

## 6. Summary: from one big table to our five tables

Start with one unnormalized sheet:

| member_name | email | plan_name | price | start | end | payment_amount | payment_date | attended_dates |
|---|---|---|---|---|---|---|---|---|
| Aarav | a@x.com | Annual | 14000 | ... | ... | 14000 | ... | 3 Oct, 4 Oct, 5 Oct |

Problems: a repeating group (`attended_dates`, violates 1NF), member data repeated on every row,
plan data repeated on every row (violates 2NF/3NF). Splitting by "who/what each fact is about" gives:

```
Members, Plans            <- facts about people and products
Memberships               <- facts about a member buying a plan
Payments                  <- facts about money for a membership
Attendance                <- facts about each visit
```
