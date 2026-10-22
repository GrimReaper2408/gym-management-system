# Viva Questions and Answers

Short answers you can say out loud. Questions 1-8 are about the design, 9-14 about SQL,
15-20 about stored programs, and 21-25 about transactions.

## Database design

**1. What is a DBMS, and which one does your project use?**
A DBMS (Database Management System) is software that stores, organises and protects data and lets users query it.
This project uses MySQL 8 (the InnoDB storage engine) with a Flask (Python) web front end.

**2. Why did you need a separate Memberships table?**
Members and Plans have a many-to-many relationship (a member can buy many plans; a plan is bought by many members).
A relational database cannot store that directly, so Memberships is a bridge (associative) table holding one
`member_id` and one `plan_id` per row, plus its own attributes: start date, end date and status.

**3. What are primary and foreign keys? Give examples.**
A primary key uniquely identifies each row (`Members.member_id`). A foreign key is a column that refers to the primary key
of another table (`Memberships.member_id` refers to `Members.member_id`). Foreign keys enforce referential integrity: you
cannot create a membership for a member that does not exist.

**4. Which constraints did you use and why?**
PRIMARY KEY and FOREIGN KEY for identity and relationships; NOT NULL for required data; UNIQUE on `email` and on
`(member_id, attendance_date)`; CHECK so prices and payment amounts must be greater than 0 and `end_date >= start_date`;
DEFAULT for `total_visits` and `status`; ENUM for fixed lists such as the payment method.

**5. Why is price stored as DECIMAL and not FLOAT?**
FLOAT is approximate and can give rounding errors (0.1 + 0.2 is not exactly 0.3). DECIMAL(10,2) stores exact values, which
is required for money.

**6. Which normal form is your database in?**
Third Normal Form, with two deliberate, documented exceptions: `Memberships.end_date` (derived from start date + plan
duration, stored so it does not change if the plan is edited later) and `Members.total_visits` (a counter kept by a trigger).
See `docs/normalization.md`.

**7. What does ON DELETE RESTRICT do, and how does your app delete safely?**
RESTRICT (the default) refuses to delete a parent row that still has child rows. If you delete a member who has memberships
or attendance rows, MySQL raises error 1451, and the app catches it and shows "Cannot delete this member...". Nothing is
deleted by accident and no orphan rows are created.

**8. Why use parameterised queries?**
Values are sent separately from the SQL text (`WHERE member_id = %s`), so user input is never executed as SQL. This prevents
SQL injection, for example someone typing `'; DROP TABLE Members; --` in a form.

## SQL

**9. Difference between WHERE and HAVING?**
WHERE filters individual rows before grouping; HAVING filters groups after GROUP BY, and can use aggregates like
`COUNT(*) >= 2`.

**10. Difference between INNER JOIN and LEFT JOIN?**
INNER JOIN returns only rows with a match in both tables. LEFT JOIN returns every row from the left table, with NULLs
where the right table has no match. Example: a LEFT JOIN from Members to Memberships shows members who never bought a membership.

**11. Difference between UNION and UNION ALL?**
UNION removes duplicate rows (it needs an extra step); UNION ALL keeps all rows and is faster.

**12. What is a view? Does it store data?**
A view is a saved SELECT query that behaves like a virtual table. It stores no data of its own; each time you query it, MySQL
runs the underlying query. Ours is `v_active_memberships`.

**13. What is an index and what is the trade-off?**
An index is a sorted structure (a B-tree in InnoDB) that lets MySQL find rows without scanning the whole table. Reads become
faster, but it uses extra space and every INSERT/UPDATE/DELETE must also update the index.

**14. What does EXPLAIN show?**
The execution plan of a query: which table is read, whether an index is used (`key`), how it reads (`type`, where `ALL` means
a full table scan) and the estimated number of rows examined.

## Stored programs

**15. Difference between a procedure and a function?**
A procedure is run with `CALL`, can have IN/OUT parameters and may return result sets or modify data. A function returns exactly
one value and can be used inside a query, e.g. `SELECT GetMembershipStatus(membership_id) ...`.

**16. What is a cursor? Where did you use one?**
A cursor reads the rows of a query one at a time inside a stored program. Steps: DECLARE, OPEN, FETCH in a loop, CLOSE.
`ShowExpiringMemberships` uses a cursor to loop over memberships ending in the next 7 days. A `NOT FOUND` handler sets a flag
to stop the loop when there are no more rows.

**17. What is a trigger? Explain your trigger.**
A trigger is code that MySQL runs automatically when an INSERT, UPDATE or DELETE happens. `AfterAttendanceInsert` runs after every
new row in Attendance and adds 1 to that member's `total_visits`.

**18. Why is the "one check-in per day" rule a constraint and not a trigger?**
A UNIQUE constraint can express that rule declaratively, so it is simpler and safer. Triggers are for actions a constraint
cannot perform, like updating another table. We avoid implementing the same rule twice.

**19. How does exception handling work in MySQL?**
You declare a handler: `DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...'`. When that error occurs,
the handler runs. EXIT leaves the block; CONTINUE carries on. `SIGNAL SQLSTATE '45000'` raises our own, user-defined error.

**20. Is MySQL's procedural SQL the same as Oracle PL/SQL?**
No. They solve the same problems but the syntax differs: MySQL uses `DECLARE ... HANDLER` instead of an `EXCEPTION` block,
`SIGNAL` instead of `RAISE_APPLICATION_ERROR`, and has no packages. See `docs/DBMS_theory.md` for the comparison table.

## Transactions and concurrency

**21. What is a transaction? Explain ACID.**
A transaction is a group of statements executed as one unit. Atomicity: all or nothing. Consistency: the database goes from one
valid state to another. Isolation: concurrent transactions do not interfere. Durability: committed data survives a crash.

**22. Show atomicity in your project.**
`AssignAndPay` inserts a membership and then a payment inside one transaction. If the payment fails (for example a negative
amount violates the CHECK), the handler runs `ROLLBACK`, so the membership is removed too. Both rows are saved or neither is.

**23. What is the difference between COMMIT, ROLLBACK and SAVEPOINT?**
COMMIT makes changes permanent; ROLLBACK undoes everything since `START TRANSACTION`; a SAVEPOINT is a bookmark, and
`ROLLBACK TO SAVEPOINT name` undoes only the work after that bookmark while keeping the transaction open.

**24. What is a deadlock, and how does InnoDB handle it?**
A deadlock is when two transactions each hold a lock the other needs, so both wait forever. InnoDB detects the cycle
immediately, rolls back one transaction (the victim) and returns error 1213; the application can retry that transaction.
Wait-die and wound-wait are timestamp schemes that prevent deadlocks by always letting waiting go from old to young
(wait-die) or young to old (wound-wait).

**25. What is a conflict-serializable schedule, and how do you test it?**
A concurrent schedule is conflict serializable if it can be converted into a serial schedule by swapping non-conflicting
operations. Draw a precedence graph (a node per transaction, an edge Ti -> Tj when an operation of Ti conflicts with a later
operation of Tj). If the graph has no cycle, the schedule is conflict serializable. An example with and without a cycle is in
`transactions.sql` Part 6 and `docs/DBMS_theory.md`.
