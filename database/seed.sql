-- =====================================================================
-- seed.sql  -  fictional sample data
-- RUN AFTER schema.sql.
--
-- All dates are written relative to today (CURDATE()), so the "active" and
-- "expired" examples stay correct no matter when you run this file.
-- Insert order respects the foreign keys:
--     Plans, Members -> Memberships -> Payments, Attendance
-- =====================================================================

USE gym_management;

-- ---------------------------------------------------------------------
-- 3 plans (prices in rupees)
-- ---------------------------------------------------------------------
INSERT INTO Plans (plan_id, plan_name, duration_months, price) VALUES
    (1, 'Monthly',   1,  1500.00),
    (2, 'Quarterly', 3,  4000.00),
    (3, 'Annual',   12, 14000.00);

-- ---------------------------------------------------------------------
-- 10 members (member 10 deliberately has no membership and no attendance;
-- this is handy for the LEFT JOIN example and for testing "delete member")
-- ---------------------------------------------------------------------
INSERT INTO Members (member_id, name, phone, email, join_date) VALUES
    (1,  'Aarav Sharma',  '9876500001', 'aarav.sharma@example.com',  DATE_SUB(CURDATE(), INTERVAL 120 DAY)),
    (2,  'Diya Patel',    '9876500002', 'diya.patel@example.com',    DATE_SUB(CURDATE(), INTERVAL 130 DAY)),
    (3,  'Rohan Mehta',   '9876500003', 'rohan.mehta@example.com',   DATE_SUB(CURDATE(), INTERVAL 70 DAY)),
    (4,  'Ananya Iyer',   '9876500004', 'ananya.iyer@example.com',   DATE_SUB(CURDATE(), INTERVAL 40 DAY)),
    (5,  'Kabir Singh',   '9876500005', 'kabir.singh@example.com',   DATE_SUB(CURDATE(), INTERVAL 65 DAY)),
    (6,  'Meera Nair',    '9876500006', 'meera.nair@example.com',    DATE_SUB(CURDATE(), INTERVAL 260 DAY)),
    (7,  'Vikram Rao',    '9876500007', 'vikram.rao@example.com',    DATE_SUB(CURDATE(), INTERVAL 210 DAY)),
    (8,  'Isha Kulkarni', '9876500008', 'isha.kulkarni@example.com', DATE_SUB(CURDATE(), INTERVAL 25 DAY)),
    (9,  'Arjun Desai',   '9876500009', 'arjun.desai@example.com',   DATE_SUB(CURDATE(), INTERVAL 50 DAY)),
    (10, 'Sneha Joshi',   '9876500010', 'sneha.joshi@example.com',   DATE_SUB(CURDATE(), INTERVAL 10 DAY));

-- ---------------------------------------------------------------------
-- 12 memberships.
-- Step 1: insert with end_date = start_date (a placeholder that satisfies
--         the CHECK end_date >= start_date).
-- Step 2: one UPDATE fills in the real end_date = start_date + plan duration,
--         the same rule the AssignMembership procedure uses.
--
--   ids 1,2,3,4,5,8  -> Active  (3 and 4 expire within the next 7 days)
--   ids 6,7,9,10,11,12 -> Expired
-- ---------------------------------------------------------------------
INSERT INTO Memberships (membership_id, member_id, plan_id, start_date, end_date, status) VALUES
    (1,  1, 3, DATE_SUB(CURDATE(), INTERVAL 100 DAY), DATE_SUB(CURDATE(), INTERVAL 100 DAY), 'Active'),
    (2,  2, 2, DATE_SUB(CURDATE(), INTERVAL 30 DAY),  DATE_SUB(CURDATE(), INTERVAL 30 DAY),  'Active'),
    (3,  3, 1, DATE_SUB(DATE_ADD(CURDATE(), INTERVAL 3 DAY), INTERVAL 1 MONTH),
               DATE_SUB(DATE_ADD(CURDATE(), INTERVAL 3 DAY), INTERVAL 1 MONTH), 'Active'),
    (4,  4, 1, DATE_SUB(DATE_ADD(CURDATE(), INTERVAL 6 DAY), INTERVAL 1 MONTH),
               DATE_SUB(DATE_ADD(CURDATE(), INTERVAL 6 DAY), INTERVAL 1 MONTH), 'Active'),
    (5,  5, 2, DATE_SUB(CURDATE(), INTERVAL 60 DAY),  DATE_SUB(CURDATE(), INTERVAL 60 DAY),  'Active'),
    (6,  6, 1, DATE_SUB(CURDATE(), INTERVAL 90 DAY),  DATE_SUB(CURDATE(), INTERVAL 90 DAY),  'Expired'),
    (7,  7, 2, DATE_SUB(CURDATE(), INTERVAL 200 DAY), DATE_SUB(CURDATE(), INTERVAL 200 DAY), 'Expired'),
    (8,  8, 3, DATE_SUB(CURDATE(), INTERVAL 20 DAY),  DATE_SUB(CURDATE(), INTERVAL 20 DAY),  'Active'),
    (9,  9, 1, DATE_SUB(CURDATE(), INTERVAL 45 DAY),  DATE_SUB(CURDATE(), INTERVAL 45 DAY),  'Expired'),
    (10, 2, 1, DATE_SUB(CURDATE(), INTERVAL 100 DAY), DATE_SUB(CURDATE(), INTERVAL 100 DAY), 'Expired'),
    (11, 3, 1, DATE_SUB(CURDATE(), INTERVAL 65 DAY),  DATE_SUB(CURDATE(), INTERVAL 65 DAY),  'Expired'),
    (12, 6, 2, DATE_SUB(CURDATE(), INTERVAL 250 DAY), DATE_SUB(CURDATE(), INTERVAL 250 DAY), 'Expired');

UPDATE Memberships ms
JOIN Plans p ON p.plan_id = ms.plan_id
SET ms.end_date = DATE_ADD(ms.start_date, INTERVAL p.duration_months MONTH);

-- ---------------------------------------------------------------------
-- 11 payments: one per membership, EXCEPT membership 9 (left unpaid on
-- purpose so the "memberships without payments" LEFT JOIN query has a
-- result). Amount = the plan price, date = the membership start date.
-- ELT() picks Cash / Card / UPI in rotation.
-- ---------------------------------------------------------------------
INSERT INTO Payments (membership_id, amount, payment_date, payment_method)
SELECT ms.membership_id,
       p.price,
       ms.start_date,
       ELT(1 + MOD(ms.membership_id, 3), 'Cash', 'Card', 'UPI')
FROM Memberships ms
JOIN Plans p ON p.plan_id = ms.plan_id
WHERE ms.membership_id <> 9
ORDER BY ms.membership_id;

-- ---------------------------------------------------------------------
-- 12 attendance rows (3 of them are for today). Only members with an
-- active membership appear. UNIQUE (member_id, attendance_date) holds.
-- ---------------------------------------------------------------------
INSERT INTO Attendance (member_id, attendance_date, check_in_time) VALUES
    (1, CURDATE(),                           '06:30:00'),
    (2, CURDATE(),                           '07:15:00'),
    (5, CURDATE(),                           '18:05:00'),
    (1, DATE_SUB(CURDATE(), INTERVAL 1 DAY), '06:45:00'),
    (3, DATE_SUB(CURDATE(), INTERVAL 1 DAY), '19:00:00'),
    (8, DATE_SUB(CURDATE(), INTERVAL 1 DAY), '17:30:00'),
    (2, DATE_SUB(CURDATE(), INTERVAL 2 DAY), '07:20:00'),
    (4, DATE_SUB(CURDATE(), INTERVAL 2 DAY), '18:45:00'),
    (1, DATE_SUB(CURDATE(), INTERVAL 3 DAY), '06:35:00'),
    (5, DATE_SUB(CURDATE(), INTERVAL 3 DAY), '18:10:00'),
    (8, DATE_SUB(CURDATE(), INTERVAL 4 DAY), '17:40:00'),
    (3, DATE_SUB(CURDATE(), INTERVAL 5 DAY), '19:10:00');

-- ---------------------------------------------------------------------
-- Sync the visit counter. If the trigger AfterAttendanceInsert already
-- exists it has counted these rows; if it does not exist yet, this makes
-- the counter correct anyway. Either way the result is identical.
-- ---------------------------------------------------------------------
UPDATE Members m
SET m.total_visits = (SELECT COUNT(*) FROM Attendance a WHERE a.member_id = m.member_id);

-- Quick check: expected 3 plans, 10 members, 12 memberships, 11 payments, 12 attendance rows.
SELECT (SELECT COUNT(*) FROM Plans)       AS plans,
       (SELECT COUNT(*) FROM Members)     AS members,
       (SELECT COUNT(*) FROM Memberships) AS memberships,
       (SELECT COUNT(*) FROM Payments)    AS payments,
       (SELECT COUNT(*) FROM Attendance)  AS attendance;
