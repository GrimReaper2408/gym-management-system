-- =====================================================================
-- transactions.sql  -  Transactions and concurrency (Unit V) with InnoDB
-- RUN AFTER schema.sql, seed.sql and stored_programs.sql.
--
-- Parts 1-5 run top to bottom as ONE session and leave the sample data
-- exactly as it was (every change is rolled back or undone).
-- Part 7 (two-session locking) must be typed by hand in two windows; it is
-- written as comments so running this file never hangs.
--
-- Contents
--   1. START TRANSACTION + COMMIT
--   2. ROLLBACK
--   3. SAVEPOINT
--   4. Atomicity: membership + payment saved together (procedure AssignAndPay)
--   5. ACID properties explained with this project
--   6. Serial vs concurrent schedules and a precedence graph
--   7. Two-session locking demo (InnoDB row locks) and a deadlock
-- =====================================================================

USE gym_management;

-- By default MySQL is in autocommit mode: every single statement is its own
-- transaction and is saved immediately. START TRANSACTION switches autocommit
-- off until COMMIT or ROLLBACK.
SELECT @@autocommit AS autocommit_is_on, @@transaction_isolation AS isolation_level;

-- ---------------------------------------------------------------------
-- 1. START TRANSACTION and COMMIT
--    COMMIT makes the changes permanent and visible to other sessions.
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE Plans SET price = price + 100 WHERE plan_id = 1;   -- 1500 -> 1600
SELECT plan_id, plan_name, price FROM Plans WHERE plan_id = 1;
COMMIT;                                                    -- the change is now permanent

-- Put the price back (a second, separate committed transaction).
START TRANSACTION;
UPDATE Plans SET price = price - 100 WHERE plan_id = 1;   -- 1600 -> 1500
COMMIT;
SELECT plan_id, plan_name, price FROM Plans WHERE plan_id = 1;

-- ---------------------------------------------------------------------
-- 2. ROLLBACK
--    ROLLBACK cancels every change made since START TRANSACTION.
-- ---------------------------------------------------------------------
START TRANSACTION;
UPDATE Plans SET price = price * 2 WHERE plan_id = 1;     -- a "mistake": 1500 -> 3000
SELECT plan_id, price AS price_inside_transaction FROM Plans WHERE plan_id = 1;
ROLLBACK;                                                  -- mistake undone
SELECT plan_id, price AS price_after_rollback FROM Plans WHERE plan_id = 1;   -- back to 1500

-- ---------------------------------------------------------------------
-- 3. SAVEPOINT
--    A savepoint is a bookmark inside a transaction. ROLLBACK TO SAVEPOINT
--    undoes only the work done after the bookmark.
-- ---------------------------------------------------------------------
START TRANSACTION;

UPDATE Plans SET price = price + 50 WHERE plan_id = 1;    -- step A
SAVEPOINT after_step_a;

UPDATE Plans SET price = price + 50 WHERE plan_id = 2;    -- step B
SELECT plan_id, price FROM Plans WHERE plan_id IN (1, 2); -- both changed

ROLLBACK TO SAVEPOINT after_step_a;                       -- undo step B only
SELECT plan_id, price FROM Plans WHERE plan_id IN (1, 2); -- plan 1 still +50, plan 2 back to normal

RELEASE SAVEPOINT after_step_a;
ROLLBACK;                                                  -- finally undo everything (data unchanged)
SELECT plan_id, price FROM Plans WHERE plan_id IN (1, 2);

-- ---------------------------------------------------------------------
-- 4. ATOMICITY: a membership and its payment are saved together or not at all.
--
--    Without a transaction, a failure between the two inserts could leave a
--    membership with no payment. AssignAndPay wraps both steps in one
--    transaction:
--       success                      -> COMMIT  (both rows saved)
--       any error (EXIT HANDLER)     -> ROLLBACK (neither row saved)
--    The failing example uses a negative amount, which the CHECK constraint
--    on Payments rejects (error 3819) AFTER the membership row was inserted;
--    the ROLLBACK removes that membership too.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS AssignAndPay;

DELIMITER $$

CREATE PROCEDURE AssignAndPay(
    IN p_member_id INT,
    IN p_plan_id   INT,
    IN p_amount    DECIMAL(10,2),
    IN p_method    VARCHAR(10)
)
BEGIN
    DECLARE v_membership_id INT;

    -- If ANY SQL error happens below, undo the whole transaction.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'FAILED: transaction rolled back, nothing was saved' AS result;
    END;

    START TRANSACTION;

    CALL AssignMembership(p_member_id, p_plan_id, CURDATE());   -- step 1: insert membership
    SET v_membership_id = LAST_INSERT_ID();                      -- id of the row just created

    INSERT INTO Payments (membership_id, amount, payment_date, payment_method)
    VALUES (v_membership_id, p_amount, CURDATE(), p_method);     -- step 2: insert payment

    COMMIT;
    SELECT 'SUCCESS: membership and payment committed' AS result;
END$$

DELIMITER ;

-- Test B (failure): negative amount. Expect FAILED, and member 10 still has 0 memberships.
CALL AssignAndPay(10, 2, -500.00, 'Cash');
SELECT COUNT(*) AS memberships_of_member_10 FROM Memberships WHERE member_id = 10;   -- 0

-- Test A (success): expect SUCCESS and one membership + one payment for member 10.
CALL AssignAndPay(10, 1, 1500.00, 'Cash');
SELECT ms.membership_id, ms.start_date, ms.end_date, p.payment_id, p.amount
FROM Memberships ms
JOIN Payments p ON p.membership_id = ms.membership_id
WHERE ms.member_id = 10;

-- Clean up Test A so the sample data is unchanged (payments first, because
-- of the foreign key from Payments to Memberships).
DELETE FROM Payments
WHERE membership_id IN (SELECT membership_id FROM Memberships WHERE member_id = 10);
DELETE FROM Memberships WHERE member_id = 10;

-- ---------------------------------------------------------------------
-- 5. ACID PROPERTIES (with examples from this project)
--
--  A - Atomicity   : all steps of a transaction happen, or none do.
--                    Example: AssignAndPay saves membership + payment together.
--  C - Consistency : a transaction takes the database from one valid state
--                    to another valid state. Constraints (PRIMARY KEY,
--                    FOREIGN KEY, UNIQUE, CHECK) are what define "valid".
--                    Example: a payment of -500 is rejected, so the database
--                    never holds a negative payment.
--  I - Isolation   : concurrent transactions do not see each other's
--                    uncommitted work. InnoDB's default level is
--                    REPEATABLE READ. Example: in Part 7, Session B cannot
--                    read or change a row that Session A has locked until
--                    Session A commits.
--  D - Durability  : once COMMIT succeeds, the data survives a crash.
--                    InnoDB writes changes to its redo log (write-ahead
--                    logging) before reporting the commit as complete.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 6. SERIAL vs CONCURRENT SCHEDULES, and a PRECEDENCE GRAPH
--
--  A schedule is the order in which operations of several transactions run.
--  Data items: A = price of plan 1 (starts 1500), B = price of plan 2 (starts 4000).
--      T1: A = A + 100 ; B = B + 100     (raise both prices)
--      T2: A = A * 2   ; B = B * 2       (double both prices)
--  Notation: R1(A) = T1 reads A, W1(A) = T1 writes A.
--
--  SERIAL schedule  (T1 completely, then T2 completely)
--      R1(A) W1(A) R1(B) W1(B)  R2(A) W2(A) R2(B) W2(B)
--      Result: A = 3200, B = 8200.   (T2 then T1 would give 3100 / 8100.)
--      Serial schedules are always correct but allow no overlap (slow).
--
--  CONCURRENT schedule S1  (operations interleaved)
--      R1(A) W1(A)  R2(A) W2(A)  R1(B) W1(B)  R2(B) W2(B)
--      Conflicting pairs (same item, at least one write, different transactions):
--          on A: T1 before T2        on B: T1 before T2
--      Precedence graph:     T1 ----> T2        (no cycle)
--      => S1 is CONFLICT SERIALIZABLE, equivalent to the serial order T1, T2
--         (result A = 3200, B = 8200, the same as the serial schedule).
--
--  CONCURRENT schedule S2
--      R1(A) W1(A)  R2(A) W2(A)  R2(B) W2(B)  R1(B) W1(B)
--          on A: T1 before T2  (edge T1 -> T2)
--          on B: T2 before T1  (edge T2 -> T1)
--      Precedence graph:     T1 ----> T2
--                            T1 <---- T2          (CYCLE)
--      => S2 is NOT conflict serializable. Result A = 3200 (as if T1;T2) but
--         B = 8100 (as if T2;T1): a mixture no serial schedule can produce.
--
--  Rule: draw one node per transaction and an edge Ti -> Tj when an operation
--  of Ti conflicts with a LATER operation of Tj. No cycle = conflict
--  serializable. InnoDB's locking prevents schedules like S2 from happening.
--  (The same graphs are drawn with Mermaid in docs/DBMS_theory.md.)
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 7. TWO-SESSION LOCKING DEMO (InnoDB row locks)
--    Open TWO connections: two mysql command-line windows, or two query tabs
--    in MySQL Workbench. In each one first run:   USE gym_management;
--    Type the steps in the order shown (numbers = order in time).
--
--  7a. A writer blocks another writer (exclusive row lock)
--
--   1. SESSION 1:  START TRANSACTION;
--   2. SESSION 1:  SELECT * FROM Plans WHERE plan_id = 1 FOR UPDATE;
--                  -- locks the row of plan 1 (SELECT ... FOR UPDATE takes an exclusive lock)
--   3. SESSION 1:  UPDATE Plans SET price = price + 100 WHERE plan_id = 1;
--   4. SESSION 2:  START TRANSACTION;
--   5. SESSION 2:  UPDATE Plans SET price = price + 50 WHERE plan_id = 1;
--                  -- BLOCKS: Session 2 waits because Session 1 holds the lock
--   6. SESSION 1:  COMMIT;
--                  -- lock released; Session 2's UPDATE now completes
--   7. SESSION 2:  COMMIT;
--   8. EITHER:     SELECT price FROM Plans WHERE plan_id = 1;   -- 1650 (both updates applied)
--   9. CLEAN UP:   UPDATE Plans SET price = 1500.00 WHERE plan_id = 1;
--
--   If Session 2 waits longer than innodb_lock_wait_timeout (default 50 s) it
--   fails with ERROR 1205 (Lock wait timeout exceeded). To see the setting:
--       SELECT @@innodb_lock_wait_timeout;
--
--  7b. Isolation: uncommitted changes are invisible to other sessions
--
--   1. SESSION 1:  START TRANSACTION;
--                  UPDATE Plans SET price = 9999 WHERE plan_id = 3;
--   2. SESSION 2:  SELECT price FROM Plans WHERE plan_id = 3;   -- still 14000.00
--   3. SESSION 1:  ROLLBACK;                                    -- 9999 never became visible
--
--  7c. Deadlock (two sessions each waiting for the other)
--
--   1. SESSION 1:  START TRANSACTION;
--                  UPDATE Plans SET price = price + 1 WHERE plan_id = 1;   -- locks row 1
--   2. SESSION 2:  START TRANSACTION;
--                  UPDATE Plans SET price = price + 1 WHERE plan_id = 2;   -- locks row 2
--   3. SESSION 1:  UPDATE Plans SET price = price + 1 WHERE plan_id = 2;   -- waits for Session 2
--   4. SESSION 2:  UPDATE Plans SET price = price + 1 WHERE plan_id = 1;   -- waits for Session 1
--                  -- DEADLOCK. InnoDB detects the cycle at once and rolls back one
--                  -- session (the "victim") with:
--                  --   ERROR 1213 (40001): Deadlock found when trying to get lock;
--                  --   try restarting transaction
--   5. The surviving session:  ROLLBACK;     (and the victim is already rolled back)
--   6. Check both prices are unchanged: SELECT plan_id, price FROM Plans WHERE plan_id IN (1,2);
--      (If any price was changed, restore: UPDATE Plans SET price = 1500.00 WHERE plan_id = 1;
--                                          UPDATE Plans SET price = 4000.00 WHERE plan_id = 2;)
-- ---------------------------------------------------------------------

-- Final safety check: prices should be 1500.00 / 4000.00 / 14000.00.
SELECT plan_id, plan_name, price FROM Plans ORDER BY plan_id;
