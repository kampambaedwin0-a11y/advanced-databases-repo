-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 1: University Library Book Loans
-- Student: 202406643 Catherine Chisani

-- STEP 1: Tables and at least 3 books
DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    loan_status VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
);

INSERT INTO books (title, available_copies) VALUES
    ('Database System Concepts', 5),
    ('Computer Networks', 2),
    ('Operating Systems', 0),
    ('Introduction to Algorithms', 10);

SELECT * FROM books ORDER BY book_id;

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% -> UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 3 THEN
            RAISE NOTICE '% -> LOW on copies (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% -> SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- STEP 4: borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be at least 1)', p_qty;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF p_qty > v_available THEN
        RAISE NOTICE 'Loan REJECTED for %: requested %, only % available', p_student, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student, p_qty, 'BORROWED');

    RAISE NOTICE 'Loan RECORDED for %: % copy/copies of book %', p_student, p_qty, p_book_id;
END;
$$;

-- STEP 5: Two valid loans and one exceeding copies
CALL borrow_book(1, '202406643', 2);
CALL borrow_book(2, '202409750', 1);
CALL borrow_book(2, '202409751', 5);

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 6: return_book procedure, called twice
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty INT;
    v_status VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored.', p_loan_id, v_qty;
END;
$$;

CALL return_book(1);
CALL return_book(1);

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- STEP 7: Explicit cursor
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books WHERE available_copies <= 3 ORDER BY book_id;
    v_id INT;
    v_title VARCHAR;
    v_copies INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_id, v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: [%] % - % copies', v_id, v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: Zero copies with EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '202406643', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9: Final state
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;