-- =====================================================================
-- schema.sql  -  Gym Management System (MySQL 8.0+)
-- Creates the database and the five tables.
--
-- RUN THIS FIRST.
-- WARNING: the first line DROPS the whole gym_management database so the
-- script can be re-run from scratch. Do not run it on data you want to keep.
-- =====================================================================

DROP DATABASE IF EXISTS gym_management;
CREATE DATABASE gym_management
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE gym_management;

-- ---------------------------------------------------------------------
-- 1. Members : one row per gym member.
--    total_visits is an extra counter column. It is kept up to date
--    automatically by the trigger AfterAttendanceInsert (stored_programs.sql).
-- ---------------------------------------------------------------------
CREATE TABLE Members (
    member_id     INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    phone         VARCHAR(15)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,      -- no two members share an email
    join_date     DATE         NOT NULL,
    total_visits  INT          NOT NULL DEFAULT 0    -- maintained by a trigger
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Plans : the kinds of membership the gym sells.
--    CHECK constraints stop zero/negative prices and durations.
-- ---------------------------------------------------------------------
CREATE TABLE Plans (
    plan_id          INT AUTO_INCREMENT PRIMARY KEY,
    plan_name        VARCHAR(50)   NOT NULL UNIQUE,
    duration_months  INT           NOT NULL,
    price            DECIMAL(10,2) NOT NULL,         -- DECIMAL is exact, good for money
    CONSTRAINT chk_plan_duration CHECK (duration_months > 0),
    CONSTRAINT chk_plan_price    CHECK (price > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Memberships : a member buys a plan for a period of time.
--    This is the "bridge" table that turns the many-to-many relationship
--    between Members and Plans into two one-to-many relationships.
--    Foreign keys use the default RESTRICT rule: a member or plan that is
--    still referenced cannot be deleted (this is what makes deletes "safe").
-- ---------------------------------------------------------------------
CREATE TABLE Memberships (
    membership_id  INT AUTO_INCREMENT PRIMARY KEY,
    member_id      INT  NOT NULL,
    plan_id        INT  NOT NULL,
    start_date     DATE NOT NULL,
    end_date       DATE NOT NULL,
    status         ENUM('Active', 'Expired', 'Cancelled') NOT NULL DEFAULT 'Active',
    CONSTRAINT fk_memberships_member FOREIGN KEY (member_id) REFERENCES Members(member_id),
    CONSTRAINT fk_memberships_plan   FOREIGN KEY (plan_id)   REFERENCES Plans(plan_id),
    CONSTRAINT chk_membership_dates  CHECK (end_date >= start_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Payments : money received for a membership.
-- ---------------------------------------------------------------------
CREATE TABLE Payments (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    membership_id   INT           NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    payment_date    DATE          NOT NULL,
    payment_method  ENUM('Cash', 'Card', 'UPI') NOT NULL,
    CONSTRAINT fk_payments_membership FOREIGN KEY (membership_id) REFERENCES Memberships(membership_id),
    CONSTRAINT chk_payment_amount     CHECK (amount > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Attendance : one row each time a member checks in.
--    UNIQUE (member_id, attendance_date) = at most one check-in per member
--    per day. This is a CONSTRAINT (declarative rule), so no trigger is
--    needed for it.
-- ---------------------------------------------------------------------
CREATE TABLE Attendance (
    attendance_id    INT AUTO_INCREMENT PRIMARY KEY,
    member_id        INT  NOT NULL,
    attendance_date  DATE NOT NULL,
    check_in_time    TIME NOT NULL,
    CONSTRAINT fk_attendance_member FOREIGN KEY (member_id) REFERENCES Members(member_id),
    CONSTRAINT uq_member_per_day    UNIQUE (member_id, attendance_date)
) ENGINE=InnoDB;

-- Quick check: should list the five tables.
SHOW TABLES;
