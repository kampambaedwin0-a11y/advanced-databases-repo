-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 2: Computer Laboratory Reservations
-- Student: 202406643 Catherine Chisani

-- STEP 1: Tables and at least 3 sessions
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    session_name VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer VARCHAR(60) NOT NULL,
    workstations INT NOT NULL CHECK (workstations > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 0),
    ('Tuesday 10:00 - Database Lab', 3),
    ('Wednesday 14:00 - Networking Lab', 30),
    ('Thursday 09:00 - Web Design Lab', 20);

SELECT * FROM lab_sessions ORDER BY session_id;

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% -> FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% -> NEARLY FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% -> ENOUGH WORKSTATIONS (% workstations)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', chk;
    END LOOP;
END $$;

-- STEP 4: reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be at least 1)', p_qty;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF p_qty > v_available THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available', p_lecturer, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_qty, 'RESERVED');

    RAISE NOTICE 'Reservation RECORDED for %: % workstations in session %', p_lecturer, p_qty, p_session_id;
END;
$$;

-- STEP 5: Two valid reservations and one exceeding capacity
CALL reserve_workstations(3, 'Dr Banda', 10);
CALL reserve_workstations(2, 'Mr Phiri', 2);
CALL reserve_workstations(2, 'Ms Mwansa', 5);

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 6: cancel_reservation procedure, called twice
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty INT;
    v_status VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. No workstations released.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstations released.', p_reservation_id, v_qty;
END;
$$;

CALL cancel_reservation(1);
CALL cancel_reservation(1);

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 7: Explicit cursor
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions WHERE available_workstations <= 5 ORDER BY session_id;
    v_id INT;
    v_name VARCHAR;
    v_avail INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_id, v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: [%] % - % available', v_id, v_name, v_avail;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Zero workstations with EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(3, 'Dr Banda', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final state
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;