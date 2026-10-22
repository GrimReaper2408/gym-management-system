-- =====================================================================
-- stored_programs.sql  -  MySQL stored programs
-- RUN AFTER schema.sql and seed.sql. The Flask app calls AddMember,
-- AssignMembership and GetMembershipStatus, so this file is required.
--
-- NOTE: MySQL does NOT use Oracle PL/SQL. These are MySQL stored
-- procedures / functions / cursors / triggers / handlers, which give the
-- equivalent ideas with different syntax (see docs/DBMS_theory.md).
--
-- DELIMITER: the mysql client ends a statement at ';'. A procedure body
-- contains many ';', so we temporarily switch the delimiter to $$.
--
-- Contents
--   1. Procedure AddMember                 (+ exception handler, SIGNAL)
--   2. Procedure AssignMembership          (+ exception handler, SIGNAL)
--   3. Function  GetMembershipStatus
--   4. Procedure ShowExpiringMemberships   (cursor)
--   5. Trigger   AfterAttendanceInsert
--   6. Tests for every program (bottom of the file)
-- =====================================================================

USE gym_management;

-- Safe to re-run: remove old versions first.
DROP PROCEDURE IF EXISTS AddMember;
DROP PROCEDURE IF EXISTS AssignMembership;
DROP FUNCTION  IF EXISTS GetMembershipStatus;
DROP PROCEDURE IF EXISTS ShowExpiringMemberships;
DROP TRIGGER   IF EXISTS AfterAttendanceInsert;

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. AddMember : insert a new member.
--
-- Exception handling (item 6): the UNIQUE constraint on email makes MySQL
-- raise error 1062 ("duplicate entry") when the email already exists.
-- The EXIT HANDLER catches exactly that error and re-raises it as a clear,
-- user-friendly error with SIGNAL SQLSTATE '45000'
-- ('45000' = "unhandled user-defined exception").
-- The uniqueness rule itself lives in the CONSTRAINT; the procedure only
-- translates its error message, so the rule is not implemented twice.
-- ---------------------------------------------------------------------
CREATE PROCEDURE AddMember(
    IN p_name      VARCHAR(100),
    IN p_phone     VARCHAR(15),
    IN p_email     VARCHAR(100),
    IN p_join_date DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR 1062
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email already registered';

    INSERT INTO Members (name, phone, email, join_date)
    VALUES (p_name, p_phone, p_email, p_join_date);
END$$

-- ---------------------------------------------------------------------
-- 2. AssignMembership : give a member a plan and calculate the end date.
--    end_date = start_date + the plan's duration_months.
--
-- Exception handling:
--   * Unknown plan  -> the SELECT finds nothing, v_months stays NULL, and we
--                      raise our own error with SIGNAL (a rule the foreign
--                      key cannot report in a friendly way, because we need
--                      the plan's duration BEFORE inserting).
--   * Unknown member -> the foreign key raises error 1452; the handler turns
--                      it into a friendly message.
-- ---------------------------------------------------------------------
CREATE PROCEDURE AssignMembership(
    IN p_member_id  INT,
    IN p_plan_id    INT,
    IN p_start_date DATE
)
BEGIN
    DECLARE v_months INT;

    -- 1452 = foreign key violation (member_id not found in Members)
    DECLARE EXIT HANDLER FOR 1452
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Member does not exist';

    SELECT duration_months INTO v_months
    FROM Plans
    WHERE plan_id = p_plan_id;

    IF v_months IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Plan does not exist';
    END IF;

    INSERT INTO Memberships (member_id, plan_id, start_date, end_date, status)
    VALUES (p_member_id, p_plan_id, p_start_date,
            DATE_ADD(p_start_date, INTERVAL v_months MONTH), 'Active');
END$$

-- ---------------------------------------------------------------------
-- 3. GetMembershipStatus : returns 'Active' or 'Expired'.
--    Active  = stored status is 'Active' AND today lies between start_date
--              and end_date.
--    Anything else (past end date, cancelled) = 'Expired'.
--    Returns 'Not found' if the membership id does not exist.
--
-- READS SQL DATA tells MySQL the function only reads tables (required when
-- binary logging is on, which is the MySQL 8 default).
-- ---------------------------------------------------------------------
CREATE FUNCTION GetMembershipStatus(p_membership_id INT)
RETURNS VARCHAR(10)
READS SQL DATA
BEGIN
    DECLARE v_status VARCHAR(10);
    DECLARE v_start  DATE;
    DECLARE v_end    DATE;

    SELECT status, start_date, end_date
    INTO   v_status, v_start, v_end
    FROM   Memberships
    WHERE  membership_id = p_membership_id;

    IF v_status IS NULL THEN
        RETURN 'Not found';
    ELSEIF v_status = 'Active' AND CURDATE() BETWEEN v_start AND v_end THEN
        RETURN 'Active';
    ELSE
        RETURN 'Expired';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 4. ShowExpiringMemberships : CURSOR example.
--    A cursor reads the rows of a query one at a time.
--    Steps: DECLARE cursor -> OPEN -> FETCH in a loop -> CLOSE.
--    The NOT FOUND handler sets v_done = 1 when FETCH runs out of rows,
--    which is how the loop knows when to stop.
--    Each fetched row is copied into a temporary table with the number of
--    days left; the procedure finishes by showing that table.
-- ---------------------------------------------------------------------
CREATE PROCEDURE ShowExpiringMemberships()
BEGIN
    DECLARE v_done          INT DEFAULT 0;
    DECLARE v_membership_id INT;
    DECLARE v_member_name   VARCHAR(100);
    DECLARE v_end_date      DATE;

    -- Order matters in MySQL: variables, then cursors, then handlers.
    DECLARE expiring_cursor CURSOR FOR
        SELECT ms.membership_id, m.name, ms.end_date
        FROM   Memberships ms
        JOIN   Members m ON m.member_id = ms.member_id
        WHERE  ms.status = 'Active'
          AND  ms.end_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
        ORDER BY ms.end_date;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    DROP TEMPORARY TABLE IF EXISTS expiring_report;
    CREATE TEMPORARY TABLE expiring_report (
        membership_id INT,
        member_name   VARCHAR(100),
        end_date      DATE,
        days_left     INT
    );

    OPEN expiring_cursor;

    read_loop: LOOP
        FETCH expiring_cursor INTO v_membership_id, v_member_name, v_end_date;
        IF v_done = 1 THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO expiring_report
        VALUES (v_membership_id, v_member_name, v_end_date, DATEDIFF(v_end_date, CURDATE()));
    END LOOP;

    CLOSE expiring_cursor;

    SELECT * FROM expiring_report;
END$$

-- ---------------------------------------------------------------------
-- 5. AfterAttendanceInsert : TRIGGER example.
--    Fires automatically after every INSERT into Attendance and adds 1 to
--    that member's total_visits counter (NEW.member_id = the new row's member).
--
--    Why a trigger and not a constraint?
--      A CONSTRAINT can only reject bad data (e.g. UNIQUE stops a second
--      check-in on the same day). It cannot update ANOTHER table.
--      A TRIGGER can run an action, so it is the right tool for keeping a
--      counter in sync. The "one check-in per day" rule stays a constraint;
--      the trigger does not repeat it.
--    Limitation (kept simple on purpose): deleting attendance rows does not
--      decrease the counter, because the app never deletes attendance.
-- ---------------------------------------------------------------------
CREATE TRIGGER AfterAttendanceInsert
AFTER INSERT ON Attendance
FOR EACH ROW
BEGIN
    UPDATE Members
    SET    total_visits = total_visits + 1
    WHERE  member_id = NEW.member_id;
END$$

DELIMITER ;

-- =====================================================================
-- 6. TESTS  (run after the programs above are created)
-- Everything between START TRANSACTION and ROLLBACK is undone at the end,
-- so the sample data is left untouched. (AUTO_INCREMENT numbers are not
-- rolled back, so the next new member/membership id will skip a number.
-- That is normal MySQL behaviour.)
-- =====================================================================
START TRANSACTION;

-- Test 1: AddMember. Expect one new row, total_visits = 0.
CALL AddMember('Test User', '9000000000', 'test.user@example.com', CURDATE());
SET @new_member = LAST_INSERT_ID();
SELECT member_id, name, email, total_visits FROM Members WHERE member_id = @new_member;

-- Test 2: AssignMembership. Quarterly plan (id 2) starting today:
-- expect end_date = today + 3 months.
CALL AssignMembership(@new_member, 2, CURDATE());
SET @new_membership = LAST_INSERT_ID();
SELECT membership_id, member_id, plan_id, start_date, end_date, status
FROM Memberships WHERE membership_id = @new_membership;

-- Test 3: GetMembershipStatus. Expect 'Active' for the new membership.
SELECT GetMembershipStatus(@new_membership) AS new_membership_status;

-- Test 3b: the function on every seeded membership.
-- Expect Active for ids 1,2,3,4,5,8 and Expired for 6,7,9,10,11,12.
SELECT membership_id, status AS stored_status, end_date,
       GetMembershipStatus(membership_id) AS computed_status
FROM Memberships
ORDER BY membership_id;

-- Test 4: Trigger. Insert an attendance row and watch total_visits go 0 -> 1.
INSERT INTO Attendance (member_id, attendance_date, check_in_time)
VALUES (@new_member, CURDATE(), CURTIME());
SELECT member_id, name, total_visits FROM Members WHERE member_id = @new_member;

-- Test 5: Cursor procedure. Expect memberships 3 and 4 (ending within 7 days).
CALL ShowExpiringMemberships();

ROLLBACK;

-- ---------------------------------------------------------------------
-- Test 6: Exception handling. Each statement below is SUPPOSED TO FAIL.
-- A failing statement stops a script, so they are commented out: run them
-- ONE AT A TIME (copy a line into the mysql client or Workbench).
--
--   -- duplicate email (aarav's email is already in the seed data)
--   CALL AddMember('Dup', '9000000001', 'aarav.sharma@example.com', CURDATE());
--   --> ERROR 1644 (45000): Email already registered
--
--   -- plan 99 does not exist
--   CALL AssignMembership(1, 99, CURDATE());
--   --> ERROR 1644 (45000): Plan does not exist
--
--   -- member 999 does not exist
--   CALL AssignMembership(999, 1, CURDATE());
--   --> ERROR 1644 (45000): Member does not exist
--
--   -- second check-in for the same member on the same day (blocked by the
--   -- UNIQUE constraint, not by the trigger). Member 1 already has a row today.
--   INSERT INTO Attendance (member_id, attendance_date, check_in_time)
--   VALUES (1, CURDATE(), CURTIME());
--   --> ERROR 1062 (23000): Duplicate entry ... for key 'Attendance.uq_member_per_day'
-- ---------------------------------------------------------------------

-- Handy: list the stored programs that now exist.
SHOW PROCEDURE STATUS WHERE Db = 'gym_management';
SHOW FUNCTION  STATUS WHERE Db = 'gym_management';
SHOW TRIGGERS;
