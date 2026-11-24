-- ICT371 Advanced Database | Question 1: Pharmacy Stock and Daily Sales
-- Student: Edwin Kampamba (202406643) | PostgreSQL 14+ with pg_cron
DROP SCHEMA IF EXISTS q1 CASCADE;
CREATE SCHEMA q1;
SET search_path TO q1, public;

-- (a) TABLES --------------------------------------------------------------
CREATE TABLE medicines (
    medicine_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL UNIQUE,
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    stock_qty     INT NOT NULL CHECK (stock_qty >= 0)
);
CREATE TABLE sales (
    sale_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
    quantity    INT NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    sold_on     DATE NOT NULL DEFAULT CURRENT_DATE
);
CREATE TABLE stock_audit (
    audit_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
    old_qty     INT NOT NULL,
    new_qty     INT NOT NULL,
    changed_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE TABLE daily_sales (
    sales_date   DATE PRIMARY KEY,
    total_qty    INT NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL
);

-- (b) FUNCTION ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INT, p_quantity INT)
RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE v_price NUMERIC;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be positive)', p_quantity;
    END IF;
    SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown medicine_id: %', p_medicine_id;
    END IF;
    RETURN v_price * p_quantity;
END $$;

-- (c) PROCEDURE -----------------------------------------------------------
-- A procedure runs in one transaction: any RAISE rolls back the sale insert
-- and the stock update together, so an invalid sale changes nothing.
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INT, p_quantity INT, p_sold_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC; v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %', p_quantity;
    END IF;
    IF p_sold_on IS NULL THEN
        RAISE EXCEPTION 'Sale date is required';
    END IF;
    -- lock the row so two concurrent sales cannot oversell
    SELECT unit_price, stock_qty INTO v_price, v_stock
      FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown medicine_id: %', p_medicine_id;
    END IF;
    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for medicine %: requested %, available %',
                        p_medicine_id, p_quantity, v_stock;
    END IF;
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on)
    VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);
    UPDATE medicines SET stock_qty = stock_qty - p_quantity   -- deducted exactly once
     WHERE medicine_id = p_medicine_id;
END $$;

-- (d) TRIGGER -------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_stock_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO stock_audit (medicine_id, old_qty, new_qty)
    VALUES (NEW.medicine_id, OLD.stock_qty, NEW.stock_qty);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_medicines_stock_audit
AFTER UPDATE ON medicines
FOR EACH ROW
WHEN (OLD.stock_qty IS DISTINCT FROM NEW.stock_qty)
EXECUTE FUNCTION trg_stock_audit();

-- (e) VIEW ----------------------------------------------------------------
CREATE OR REPLACE VIEW v_low_stock AS
SELECT medicine_id, medicine_name, unit_price, stock_qty AS remaining_stock
FROM medicines
WHERE stock_qty < 10;

-- (f) INDEX ---------------------------------------------------------------
-- Equality column (medicine_id) first, range column (sold_on) second: the
-- B-tree jumps to one medicine and reads its dates in order, no sorting.
CREATE INDEX idx_sales_medicine_sold_on ON sales (medicine_id, sold_on);

-- (g) SCHEDULED JOB -------------------------------------------------------
-- Recomputes from the sales table and upserts, so reruns never double-count.
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO daily_sales (sales_date, total_qty, total_amount)
    SELECT p_day, COALESCE(SUM(quantity), 0), COALESCE(SUM(quantity * unit_price), 0)
      FROM sales WHERE sold_on = p_day
    ON CONFLICT (sales_date) DO UPDATE
       SET total_qty = EXCLUDED.total_qty, total_amount = EXCLUDED.total_amount;
END $$;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('q1_refresh_sales', '15 0 * * *',
                     $$CALL q1.pr_refresh_sales(CURRENT_DATE - 1)$$);

-- SEED DATA (sales loaded through the procedure) -------------------------
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES
 ('Paracetamol 500mg', 2.50, 100),
 ('Amoxicillin 250mg', 8.00,  30),
 ('Ibuprofen 200mg',   4.25,  12);

CALL pr_record_sale(1, 10, CURRENT_DATE - 1);
CALL pr_record_sale(1,  5, CURRENT_DATE - 1);
CALL pr_record_sale(2, 12, CURRENT_DATE - 1);
CALL pr_record_sale(2, 10, CURRENT_DATE);
CALL pr_record_sale(3,  3, CURRENT_DATE);
CALL pr_record_sale(3,  2, CURRENT_DATE);

-- DEMONSTRATIONS ----------------------------------------------------------
SELECT fn_sale_value(1, 4) AS value_of_4_paracetamol;       -- 10.00
SELECT * FROM medicines ORDER BY 1;
SELECT * FROM stock_audit ORDER BY 1;                         -- 6 audit rows

-- Invalid sale: rejected, nothing changes
DO $$ BEGIN
    CALL pr_record_sale(3, 999, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected: %', SQLERRM;
END $$;
SELECT * FROM medicines WHERE medicine_id = 3;                -- stock still 7

-- (e) query the view after the sales
SELECT * FROM v_low_stock;                                    -- Amoxicillin 8, Ibuprofen 7

-- (f) EXPLAIN (seqscan disabled only because the demo table is tiny)
ANALYZE sales;
SET enable_seqscan = off;
EXPLAIN SELECT * FROM sales
WHERE medicine_id = 1 AND sold_on BETWEEN CURRENT_DATE - 7 AND CURRENT_DATE;
RESET enable_seqscan;

-- (g) run twice: totals must be identical (no double counting)
CALL pr_refresh_sales(CURRENT_DATE - 1);
CALL pr_refresh_sales(CURRENT_DATE - 1);
CALL pr_refresh_sales(CURRENT_DATE);
SELECT * FROM daily_sales ORDER BY 1;
SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobname = 'q1_refresh_sales';
