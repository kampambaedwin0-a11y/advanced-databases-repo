-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student: 202406643 Catherine Chisani

-- STEP 1: Tables and at least 3 medicines
DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id SERIAL PRIMARY KEY,
    medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 8),
    ('Cough Syrup', 0),
    ('Oral Rehydration Salts', 40);

SELECT * FROM medicines ORDER BY medicine_id;

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% -> OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 10 THEN
            RAISE NOTICE '% -> LOW STOCK (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% -> SUFFICIENTLY STOCKED (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Stock review day %', d;
        d := d + 1;
    END LOOP;

    FOR insp IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', insp;
    END LOOP;
END $$;

-- STEP 4: dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be at least 1)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF p_qty > v_stock THEN
        RAISE NOTICE 'Dispensing REJECTED for %: requested %, only % in stock', p_student, p_qty, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student, p_qty, 'DISPENSED');

    RAISE NOTICE 'Dispensing RECORDED for %: % unit(s) of medicine %', p_student, p_qty, p_medicine_id;
END;
$$;

-- STEP 5: Two valid quantities and one exceeding stock
CALL dispense_medicine(1, '202406643', 20);
CALL dispense_medicine(4, '202409750', 5);
CALL dispense_medicine(2, '202409751', 20);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 6: reverse_dispensing procedure, called twice
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty INT;
    v_status VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed. Stock not restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. % unit(s) restored to stock.', p_record_id, v_qty;
END;
$$;

CALL reverse_dispensing(1);
CALL reverse_dispensing(1);

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 7: Explicit cursor (threshold 10)
DO $$
DECLARE
    v_threshold INT := 10;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines WHERE stock_quantity < p_limit ORDER BY medicine_id;
    v_id INT;
    v_name VARCHAR;
    v_stock INT;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO v_id, v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): [%] % - % in stock', v_threshold, v_id, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Negative quantity with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '202406643', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final state
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;