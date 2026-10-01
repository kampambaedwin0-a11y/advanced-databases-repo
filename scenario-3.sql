-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 3: Student Hostel Room Allocation
-- Student: 202406643 Catherine Chisani

-- STEP 1: Tables and at least 3 rooms
DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_name VARCHAR(20) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id INT NOT NULL REFERENCES hostel_rooms(room_id),
    status VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('A101', 0),
    ('A102', 1),
    ('B201', 4),
    ('B202', 6);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % -> FULL', rec.room_name;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % -> ONE SPACE LEFT', rec.room_name;
        ELSE
            RAISE NOTICE 'Room % -> SEVERAL SPACES (%)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', chk;
    END LOOP;
END $$;

-- STEP 4: allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_student IS NULL OR TRIM(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for %: room % is full', p_student, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (TRIM(p_student), p_room_id, 'ALLOCATED');

    RAISE NOTICE 'Allocation RECORDED: student % -> room %', p_student, p_room_id;
END;
$$;

-- STEP 5: Two valid allocations and one to a full room
CALL allocate_room('202406643', 2);
CALL allocate_room('202409750', 3);
CALL allocate_room('202409751', 1);

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- STEP 6: check_out procedure, called twice
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out. No space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. One bed space released in room %.', p_allocation_id, v_room_id;
END;
$$;

CALL check_out(1);
CALL check_out(1);

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- STEP 7: Explicit cursor
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_name, available_spaces
        FROM hostel_rooms WHERE available_spaces <= 1 ORDER BY room_id;
    v_id INT;
    v_name VARCHAR;
    v_spaces INT;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_id, v_name, v_spaces;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full/nearly full: room % (id %) - % space(s) left', v_name, v_id, v_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- STEP 8: Blank student number with EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 3);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final state
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;