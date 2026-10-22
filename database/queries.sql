-- =====================================================================
-- queries.sql  -  SQL syllabus examples on the five project tables
-- RUN AFTER schema.sql and seed.sql (stored_programs.sql is NOT needed).
--
-- Every query has a short explanation above it. The file can be run in one go:
--   * all INSERT / UPDATE / DELETE / ALTER examples work on a throw-away
--     copy table (Members_demo) that is dropped at the end of section 1,
--     so the real data is never changed;
--   * section 11 creates a view and an index. Running the file a second time
--     fails at CREATE INDEX because the index already exists (MySQL has no
--     "IF NOT EXISTS" for indexes). To re-run, first execute:
--         DROP INDEX idx_attendance_date ON Attendance;
-- =====================================================================

USE gym_management;

-- =====================================================================
-- 1. DDL and DML: CREATE, ALTER, INSERT, UPDATE, DELETE (+ SELECT)
-- =====================================================================
DROP TABLE IF EXISTS Members_demo;

-- 1.1 CREATE: make a new table with the same structure as Members.
--     (The real tables are created in schema.sql.)
CREATE TABLE Members_demo LIKE Members;

-- 1.2 ALTER: add a column, widen a column, then remove the column again.
ALTER TABLE Members_demo ADD COLUMN address VARCHAR(150);
ALTER TABLE Members_demo MODIFY COLUMN phone VARCHAR(20) NOT NULL;
ALTER TABLE Members_demo DROP COLUMN address;

-- 1.3 INSERT: add two rows. Columns we leave out (member_id, total_visits)
--     get their defaults (auto-increment, 0).
INSERT INTO Members_demo (name, phone, email, join_date) VALUES
    ('Demo One', '9000000011', 'demo.one@example.com', CURDATE()),
    ('Demo Two', '9000000012', 'demo.two@example.com', CURDATE());

-- 1.4 SELECT: read every row and column.
SELECT * FROM Members_demo;

-- 1.5 UPDATE: change one row. WHERE decides which row; without it ALL rows change.
UPDATE Members_demo
SET phone = '9111111111'
WHERE email = 'demo.one@example.com';

-- 1.6 DELETE: remove one row. Again, WHERE limits the delete to that row.
DELETE FROM Members_demo
WHERE email = 'demo.two@example.com';

SELECT * FROM Members_demo;      -- one row left, with the new phone number

-- 1.7 DROP: remove the demo table (cleanup).
DROP TABLE Members_demo;

-- =====================================================================
-- 2. SELECT with WHERE, LIKE, BETWEEN, IN, ORDER BY
-- =====================================================================

-- 2.1 WHERE: members who joined in the last 60 days.
SELECT member_id, name, join_date
FROM Members
WHERE join_date >= DATE_SUB(CURDATE(), INTERVAL 60 DAY);

-- 2.2 LIKE: names starting with 'A' ('%' means "any characters").
SELECT member_id, name FROM Members WHERE name LIKE 'A%';

-- 2.3 LIKE: email addresses that contain "patel" anywhere.
SELECT name, email FROM Members WHERE email LIKE '%patel%';

-- 2.4 BETWEEN: payments from 1500 to 4000 rupees (both ends included).
SELECT payment_id, amount, payment_date
FROM Payments
WHERE amount BETWEEN 1500 AND 4000;

-- 2.5 IN: payments made by UPI or Card (shorter than two ORs).
SELECT payment_id, amount, payment_method
FROM Payments
WHERE payment_method IN ('UPI', 'Card');

-- 2.6 ORDER BY: plans from most to least expensive (DESC = descending).
SELECT plan_name, price FROM Plans ORDER BY price DESC;

-- 2.7 ORDER BY with two columns: newest attendance first, then earliest time.
SELECT member_id, attendance_date, check_in_time
FROM Attendance
ORDER BY attendance_date DESC, check_in_time ASC;

-- =====================================================================
-- 3. JOINS
-- =====================================================================

-- 3.1 INNER JOIN: only rows that match on both sides. Lists each membership
--     with the member's name and the plan's name.
SELECT m.name, p.plan_name, ms.start_date, ms.end_date
FROM Memberships ms
INNER JOIN Members m ON m.member_id = ms.member_id
INNER JOIN Plans   p ON p.plan_id   = ms.plan_id
ORDER BY ms.membership_id;

-- 3.2 LEFT JOIN: ALL rows from the left table, plus matches from the right
--     (NULL where there is no match). Every member with their memberships;
--     Sneha Joshi appears with NULLs because she has none.
SELECT m.name, ms.membership_id, ms.start_date
FROM Members m
LEFT JOIN Memberships ms ON ms.member_id = m.member_id
ORDER BY m.member_id;

-- 3.3 LEFT JOIN + IS NULL: members who have never bought a membership.
SELECT m.member_id, m.name
FROM Members m
LEFT JOIN Memberships ms ON ms.member_id = m.member_id
WHERE ms.membership_id IS NULL;

-- 3.4 LEFT JOIN + IS NULL: memberships that have no payment recorded
--     (membership 9 in the sample data).
SELECT ms.membership_id, m.name
FROM Memberships ms
JOIN Members m ON m.member_id = ms.member_id
LEFT JOIN Payments pay ON pay.membership_id = ms.membership_id
WHERE pay.payment_id IS NULL;

-- =====================================================================
-- 4. AGGREGATE FUNCTIONS: COUNT, SUM, AVG, MIN, MAX
-- =====================================================================

-- 4.1 COUNT: how many members are there?
SELECT COUNT(*) AS total_members FROM Members;

-- 4.2 SUM: total money received.
SELECT SUM(amount) AS total_received FROM Payments;

-- 4.3 AVG: average plan price (ROUND to 2 decimals).
SELECT ROUND(AVG(price), 2) AS average_plan_price FROM Plans;

-- 4.4 MIN and MAX: smallest and largest single payment.
SELECT MIN(amount) AS smallest_payment, MAX(amount) AS largest_payment FROM Payments;

-- 4.5 COUNT(DISTINCT ...): how many different members have ever checked in?
SELECT COUNT(DISTINCT member_id) AS members_who_attended FROM Attendance;

-- =====================================================================
-- 5. GROUP BY and HAVING
--    GROUP BY makes one row per group. WHERE filters rows BEFORE grouping;
--    HAVING filters groups AFTER grouping (it can use COUNT, SUM, ...).
-- =====================================================================

-- 5.1 GROUP BY: number of payments and money received per payment method.
SELECT payment_method, COUNT(*) AS payments, SUM(amount) AS total
FROM Payments
GROUP BY payment_method;

-- 5.2 GROUP BY + JOIN: how many memberships each plan has sold.
SELECT p.plan_name, COUNT(ms.membership_id) AS memberships_sold
FROM Plans p
LEFT JOIN Memberships ms ON ms.plan_id = p.plan_id
GROUP BY p.plan_id, p.plan_name;

-- 5.3 HAVING: members who have had 2 or more memberships (returning members).
SELECT m.member_id, m.name, COUNT(*) AS memberships
FROM Members m
JOIN Memberships ms ON ms.member_id = m.member_id
GROUP BY m.member_id, m.name
HAVING COUNT(*) >= 2;

-- 5.4 HAVING with SUM: plans that earned more than 10000 rupees in total.
SELECT p.plan_name, SUM(pay.amount) AS revenue
FROM Plans p
JOIN Memberships ms ON ms.plan_id = p.plan_id
JOIN Payments pay   ON pay.membership_id = ms.membership_id
GROUP BY p.plan_id, p.plan_name
HAVING SUM(pay.amount) > 10000;

-- =====================================================================
-- 6. SUBQUERIES (a query inside another query)
-- =====================================================================

-- 6.1 Scalar subquery: payments larger than the average payment.
--     The inner query returns a single number that the outer query compares with.
SELECT payment_id, amount
FROM Payments
WHERE amount > (SELECT AVG(amount) FROM Payments);

-- 6.2 Subquery with NOT IN: members who have never checked in.
SELECT member_id, name
FROM Members
WHERE member_id NOT IN (SELECT member_id FROM Attendance);

-- =====================================================================
-- 7. UNION and UNION ALL (stack the results of two queries)
-- =====================================================================

-- 7.1 UNION: removes duplicates. Every member id that appears in
--     Memberships or in Attendance, each listed once.
SELECT member_id FROM Memberships
UNION
SELECT member_id FROM Attendance;

-- 7.2 UNION ALL: keeps duplicates (faster, no duplicate check). Same query,
--     but a member id appears once for every row it has in either table.
SELECT member_id FROM Memberships
UNION ALL
SELECT member_id FROM Attendance;

-- =====================================================================
-- 8. STRING FUNCTIONS
-- =====================================================================

-- 8.1 UPPER, LOWER, LENGTH, CONCAT, SUBSTRING_INDEX, LEFT.
SELECT name,
       UPPER(name)                      AS name_upper,
       LENGTH(name)                     AS name_length,
       SUBSTRING_INDEX(email, '@', 1)   AS email_username,   -- text before the '@'
       CONCAT('+91-', phone)            AS phone_with_code,
       LEFT(phone, 5)                   AS phone_prefix
FROM Members;

-- 8.2 REPLACE and TRIM: tidy text.
SELECT REPLACE(email, '@example.com', '@gym.in') AS new_email_domain,
       TRIM('   spaces around   ')               AS trimmed
FROM Members
LIMIT 3;

-- =====================================================================
-- 9. DATE FUNCTIONS
-- =====================================================================

-- 9.1 CURDATE, DATEDIFF, DATE_FORMAT, MONTHNAME, TIMESTAMPDIFF on Members.
SELECT name,
       join_date,
       DATE_FORMAT(join_date, '%d-%b-%Y')            AS join_date_formatted,
       MONTHNAME(join_date)                          AS join_month,
       DATEDIFF(CURDATE(), join_date)                AS days_as_member,
       TIMESTAMPDIFF(MONTH, join_date, CURDATE())    AS full_months_as_member
FROM Members
ORDER BY join_date;

-- 9.2 DATE_ADD and DATEDIFF on Memberships: days left until each membership
--     ends (negative = already ended), and the date one month after the end.
SELECT membership_id, end_date,
       DATEDIFF(end_date, CURDATE())             AS days_left,
       DATE_ADD(end_date, INTERVAL 1 MONTH)      AS one_month_after_end
FROM Memberships
ORDER BY end_date;

-- 9.3 DAYNAME: how many check-ins happened on each weekday?
SELECT DAYNAME(attendance_date) AS weekday, COUNT(*) AS check_ins
FROM Attendance
GROUP BY DAYNAME(attendance_date)
ORDER BY check_ins DESC;

-- =====================================================================
-- 10. EXPLAIN (see how MySQL runs a query) -- run BEFORE the index exists
-- =====================================================================

-- 10.1 EXPLAIN shows the execution plan. Read these columns:
--        type          = ALL means a full table scan (every row is read)
--        possible_keys = indexes MySQL could use (NULL = none)
--        key           = index MySQL actually chose
--        rows          = estimated rows it must examine
--      Before the index in section 11: type = ALL, possible_keys = NULL.
EXPLAIN SELECT * FROM Attendance WHERE attendance_date = CURDATE();

-- =====================================================================
-- 11. VIEW and INDEX
-- =====================================================================

-- 11.1 VIEW: a saved query that behaves like a table (it stores no data of its
--      own). This one hides the three-table join behind a simple name.
CREATE OR REPLACE VIEW v_active_memberships AS
SELECT ms.membership_id,
       m.name        AS member_name,
       p.plan_name,
       ms.start_date,
       ms.end_date,
       DATEDIFF(ms.end_date, CURDATE()) AS days_left
FROM Memberships ms
JOIN Members m ON m.member_id = ms.member_id
JOIN Plans   p ON p.plan_id   = ms.plan_id
WHERE ms.status = 'Active'
  AND CURDATE() BETWEEN ms.start_date AND ms.end_date;

-- 11.2 Use the view exactly like a table.
SELECT * FROM v_active_memberships ORDER BY days_left;

-- 11.3 INDEX: a sorted lookup structure (like a book's index) that lets MySQL
--      find rows without reading the whole table. The dashboard asks "who
--      attended today?" on attendance_date, so we index that column.
--      Trade-off: reads get faster, but every INSERT must also update the index.
CREATE INDEX idx_attendance_date ON Attendance (attendance_date);

-- 11.4 List the indexes on the table (the new one appears at the bottom).
SHOW INDEX FROM Attendance;

-- 11.5 EXPLAIN again: possible_keys now lists idx_attendance_date. (With only 12
--      rows MySQL may still decide a full scan is cheaper; on a big table it
--      would choose the index, type = ref.)
EXPLAIN SELECT * FROM Attendance WHERE attendance_date = CURDATE();
