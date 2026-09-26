-- =====================================================================
-- Alfido Tech | Customer Behavior Analysis
-- SQL Schema & Analytical Queries
-- Engine: SQLite (portable to MySQL/PostgreSQL with minor syntax tweaks)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. SCHEMA
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS transactions;
CREATE TABLE transactions (
    customer_id     INTEGER NOT NULL,
    purchase_date   TEXT    NOT NULL,       -- ISO timestamp
    category        TEXT    NOT NULL,
    unit_price      REAL    NOT NULL,
    quantity        INTEGER NOT NULL,
    amount          REAL    NOT NULL,       -- unit_price * quantity
    payment_method  TEXT    NOT NULL,
    returned        INTEGER NOT NULL        -- 0/1 flag
);

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id         INTEGER PRIMARY KEY,
    customer_name        TEXT,
    age                  INTEGER,
    gender               TEXT,
    recency              INTEGER,           -- days since last purchase
    frequency            INTEGER,           -- number of transactions
    monetary             REAL,              -- total spend
    avg_order_value      REAL,
    return_rate          REAL,
    tenure_days          INTEGER,
    preferred_category   TEXT,
    preferred_payment    TEXT,
    r_score              INTEGER,           -- 1-5 (5 = best)
    f_score              INTEGER,
    m_score              INTEGER,
    rfm_score            TEXT,              -- concatenated e.g. '555'
    rfm_segment          TEXT,              -- Champions / Loyal / At Risk / ...
    cluster              INTEGER,           -- K-Means cluster id
    cluster_segment      TEXT,
    churn                INTEGER,           -- provided label, 0/1
    churn_probability    REAL,              -- model-estimated probability
    churn_risk_band      TEXT               -- Low / Medium / High
);

CREATE INDEX idx_tx_customer ON transactions(customer_id);
CREATE INDEX idx_cust_segment ON customers(rfm_segment);

-- ---------------------------------------------------------------------
-- 2. DATA QUALITY CHECKS
-- ---------------------------------------------------------------------

-- 2a. Duplicate transaction rows
SELECT COUNT(*) AS duplicate_rows
FROM (
    SELECT customer_id, purchase_date, category, amount, COUNT(*) c
    FROM transactions
    GROUP BY customer_id, purchase_date, category, amount
    HAVING c > 1
);

-- 2b. Transactions with non-positive amount/quantity
SELECT COUNT(*) AS bad_rows
FROM transactions
WHERE amount <= 0 OR quantity <= 0 OR unit_price <= 0;

-- ---------------------------------------------------------------------
-- 3. CUSTOMER SEGMENTATION SUMMARY (RFM)
-- ---------------------------------------------------------------------

SELECT
    rfm_segment,
    COUNT(*)                                   AS customers,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM customers), 1) AS pct_customers,
    ROUND(AVG(recency), 1)                     AS avg_recency_days,
    ROUND(AVG(frequency), 2)                   AS avg_frequency,
    ROUND(AVG(monetary), 2)                    AS avg_monetary,
    ROUND(SUM(monetary), 2)                    AS total_revenue,
    ROUND(100.0 * SUM(monetary) /
        (SELECT SUM(monetary) FROM customers), 1)  AS pct_revenue,
    ROUND(AVG(churn), 3)                       AS churn_rate
FROM customers
GROUP BY rfm_segment
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------
-- 4. TOP PRODUCT CATEGORY PER SEGMENT
-- ---------------------------------------------------------------------

WITH seg_cat AS (
    SELECT c.rfm_segment, t.category, SUM(t.amount) AS revenue,
           RANK() OVER (PARTITION BY c.rfm_segment ORDER BY SUM(t.amount) DESC) AS rnk
    FROM transactions t
    JOIN customers c ON c.customer_id = t.customer_id
    GROUP BY c.rfm_segment, t.category
)
SELECT rfm_segment, category AS top_category, ROUND(revenue, 2) AS revenue
FROM seg_cat
WHERE rnk = 1
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- 5. MONTHLY REVENUE & ORDER TREND
-- ---------------------------------------------------------------------

SELECT
    strftime('%Y-%m', purchase_date)   AS year_month,
    COUNT(*)                           AS orders,
    ROUND(SUM(amount), 2)              AS revenue,
    ROUND(AVG(amount), 2)              AS avg_order_value
FROM transactions
GROUP BY year_month
ORDER BY year_month;

-- ---------------------------------------------------------------------
-- 6. MONTHLY COHORT RETENTION
--    (% of each acquisition cohort still transacting N months later)
-- ---------------------------------------------------------------------

WITH first_purchase AS (
    SELECT customer_id, MIN(strftime('%Y-%m', purchase_date)) AS cohort_month
    FROM transactions
    GROUP BY customer_id
),
activity AS (
    SELECT t.customer_id,
           fp.cohort_month,
           strftime('%Y-%m', t.purchase_date) AS activity_month,
           (
             (CAST(strftime('%Y', t.purchase_date) AS INT) - CAST(substr(fp.cohort_month,1,4) AS INT)) * 12
             + (CAST(strftime('%m', t.purchase_date) AS INT) - CAST(substr(fp.cohort_month,6,2) AS INT))
           ) AS period_number
    FROM transactions t
    JOIN first_purchase fp ON fp.customer_id = t.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_customers
    FROM activity WHERE period_number = 0
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       a.period_number,
       COUNT(DISTINCT a.customer_id)                              AS active_customers,
       cs.cohort_customers,
       ROUND(100.0 * COUNT(DISTINCT a.customer_id) / cs.cohort_customers, 1) AS retention_pct
FROM activity a
JOIN cohort_size cs ON cs.cohort_month = a.cohort_month
GROUP BY a.cohort_month, a.period_number
ORDER BY a.cohort_month, a.period_number;

-- ---------------------------------------------------------------------
-- 7. HIGH-VALUE CUSTOMERS AT RISK (actionable retention target list)
--    Top-spending customers who have gone quiet (recency > 180 days)
-- ---------------------------------------------------------------------

SELECT customer_id, customer_name, monetary AS lifetime_spend, frequency,
       recency AS days_since_last_purchase, rfm_segment
FROM customers
WHERE recency > 180
ORDER BY monetary DESC
LIMIT 100;

-- ---------------------------------------------------------------------
-- 8. PAYMENT METHOD MIX BY SEGMENT
-- ---------------------------------------------------------------------

SELECT c.rfm_segment, t.payment_method, COUNT(*) AS transactions,
       ROUND(100.0 * COUNT(*) OVER (PARTITION BY c.rfm_segment, t.payment_method) /
             COUNT(*) OVER (PARTITION BY c.rfm_segment), 1) AS pct_of_segment
FROM transactions t
JOIN customers c ON c.customer_id = t.customer_id
GROUP BY c.rfm_segment, t.payment_method
ORDER BY c.rfm_segment, transactions DESC;

-- ---------------------------------------------------------------------
-- 9. RETURN RATE BY CATEGORY
-- ---------------------------------------------------------------------

SELECT category,
       COUNT(*)                              AS transactions,
       SUM(returned)                         AS returned_transactions,
       ROUND(100.0 * SUM(returned) / COUNT(*), 1) AS return_rate_pct
FROM transactions
GROUP BY category
ORDER BY return_rate_pct DESC;

-- ---------------------------------------------------------------------
-- 10. CHURN LABEL SANITY CHECK
--     Does the provided Churn flag correlate with segment / recency at all?
-- ---------------------------------------------------------------------

SELECT rfm_segment, ROUND(AVG(churn), 3) AS churn_rate, COUNT(*) AS customers
FROM customers
GROUP BY rfm_segment
ORDER BY churn_rate DESC;
-- Note: in this dataset, churn_rate is ~0.20 across every segment,
-- indicating the label is not behaviorally driven (see report, Section 5).
