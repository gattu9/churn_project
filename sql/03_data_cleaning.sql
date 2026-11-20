/* =========================================================
   03_data_cleaning.sql
   Customer Churn Analysis - build CLEAN tables from RAW tables
   Raw tables are never modified, so this script can be re-run.
   ========================================================= */
USE churn_db;

-- Drop old versions (monthly_usage first, because it references customers)
DROP TABLE IF EXISTS monthly_usage;
DROP TABLE IF EXISTS customers;

/* ---------------- CLEAN TABLE 1: customers ---------------- */
CREATE TABLE customers (
    customer_id         INT PRIMARY KEY,
    signup_date         DATE,
    signup_month        DATE,          -- cohort month (1st of month)
    plan_type           VARCHAR(20),
    plan_tier           VARCHAR(20),
    monthly_price       DECIMAL(6,2),
    acquisition_channel VARCHAR(30),
    primary_device      VARCHAR(20),
    age_group           VARCHAR(10),
    is_churned          INT,           -- 1 = churned, 0 = active
    churn_status        VARCHAR(10),   -- 'Churned' / 'Active'
    churn_date          DATE NULL,
    cancel_reason       VARCHAR(40) NULL,
    tenure_days         INT,
    tenure_bucket       VARCHAR(15)
);

INSERT INTO customers
SELECT
    customer_id,
    signup_date,
    DATE_FORMAT(signup_date, '%Y-%m-01'),
    LOWER(TRIM(plan_type)),
    LOWER(TRIM(plan_tier)),                                   -- fix 1
    monthly_price,
    LOWER(TRIM(acquisition_channel)),
    LOWER(TRIM(primary_device)),
    TRIM(age_group),
    CASE WHEN LOWER(TRIM(churned)) = 'yes' THEN 1 ELSE 0 END,           -- fix 3
    CASE WHEN LOWER(TRIM(churned)) = 'yes' THEN 'Churned' ELSE 'Active' END,
    churn_date,
    CASE WHEN LOWER(TRIM(churned)) = 'yes' AND cancel_reason IS NULL
         THEN 'not_provided'                                  -- fix 2
         ELSE LOWER(TRIM(cancel_reason)) END,
    -- tenure: churned -> until churn date; active -> until end of data (2025-12-31)
    DATEDIFF(COALESCE(churn_date, DATE '2025-12-31'), signup_date),
    CASE
        WHEN DATEDIFF(COALESCE(churn_date, DATE '2025-12-31'), signup_date) <= 30  THEN '0-1 month'
        WHEN DATEDIFF(COALESCE(churn_date, DATE '2025-12-31'), signup_date) <= 90  THEN '1-3 months'
        WHEN DATEDIFF(COALESCE(churn_date, DATE '2025-12-31'), signup_date) <= 180 THEN '3-6 months'
        WHEN DATEDIFF(COALESCE(churn_date, DATE '2025-12-31'), signup_date) <= 365 THEN '6-12 months'
        ELSE '12+ months'
    END
FROM raw_subscriptions;

/* ---------------- CLEAN TABLE 2: monthly_usage ---------------- */
-- Find the 99th percentile of workouts (MySQL has no PERCENTILE function,
-- so we use the CUME_DIST() window function instead)
SET @p99 = (
    SELECT MIN(workouts_completed)
    FROM (SELECT workouts_completed,
                 CUME_DIST() OVER (ORDER BY workouts_completed) AS cd
          FROM raw_usage) x
    WHERE cd >= 0.99
);

CREATE TABLE monthly_usage (
    customer_id        INT,
    usage_month        DATE,
    workouts_completed INT,
    minutes_active     DECIMAL(8,1) NULL,
    classes_booked     INT,
    support_tickets    INT,
    minutes_missing    INT,     -- 1 = minutes was blank in source (fix 6)
    is_outlier         INT,     -- 1 = workouts above 99th percentile (fix 7)
    PRIMARY KEY (customer_id, usage_month),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

INSERT INTO monthly_usage
WITH ranked AS (
    SELECT u.*,
           ROW_NUMBER() OVER (PARTITION BY customer_id, month
                              ORDER BY customer_id) AS rn
    FROM raw_usage u
)
SELECT customer_id,
       STR_TO_DATE(CONCAT(month, '-01'), '%Y-%m-%d'),          -- fix 5
       workouts_completed,
       minutes_active,
       classes_booked,
       support_tickets,
       CASE WHEN minutes_active IS NULL THEN 1 ELSE 0 END,
       CASE WHEN workouts_completed > @p99 THEN 1 ELSE 0 END
FROM ranked
WHERE rn = 1;                                                  -- fix 4

/* ---------------- VALIDATION ---------------- */
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'monthly_usage', COUNT(*) FROM monthly_usage;
-- Expect: 4200 and 30525 (30685 - 160 duplicates)

SELECT plan_tier COLLATE utf8mb4_bin AS plan_tier_exact, COUNT(*) AS customers
FROM customers
GROUP BY plan_tier_exact;
-- Expect 3 rows only: basic 1976, plus 1501, premium 723

SELECT cancel_reason, COUNT(*) AS customers
FROM customers
WHERE is_churned = 1
GROUP BY cancel_reason
ORDER BY customers DESC;
-- Expect: not_using_enough 570, not_provided 382, too_expensive 322,
--         found_alternative 175, other 162, technical_issues 157

SELECT @p99 AS workouts_p99,
       SUM(is_outlier)      AS outlier_rows,
       SUM(minutes_missing) AS missing_minutes_rows
FROM monthly_usage;
-- Expect: p99 = 18, outlier_rows about 300, missing_minutes_rows about 500

SELECT tenure_bucket, COUNT(*) AS customers
FROM customers
GROUP BY tenure_bucket
ORDER BY MIN(tenure_days);
-- Expect: 0-1 month 273, 1-3 months 732, 3-6 months 1023, 6-12 months 1632, 12+ months 540S