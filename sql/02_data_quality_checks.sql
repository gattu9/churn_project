/* =========================================================
   02_data_quality_checks.sql
   Customer Churn Analysis - profile raw data before cleaning
   ========================================================= */
USE churn_db;

-- CHECK 1: Is every customer_id unique?
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT customer_id) AS unique_customers
FROM raw_subscriptions;
-- Expect: 4200 and 4200 ✅

-- CHECK 2: Missing values
SELECT COUNT(*) - COUNT(churn_date)    AS null_churn_date,
       COUNT(*) - COUNT(cancel_reason) AS null_cancel_reason
FROM raw_subscriptions;
-- Expect: 2432 and 2814

-- CHECK 3: Category values (MySQL's default collation is case-INSENSITIVE)
SELECT plan_tier, COUNT(*) AS customers
FROM raw_subscriptions
GROUP BY plan_tier
ORDER BY plan_tier;
-- Shows 3 rows because 'Basic' and 'basic' are treated as equal

-- CHECK 3b: Case-SENSITIVE comparison reveals the hidden problem
SELECT plan_tier COLLATE utf8mb4_bin AS plan_tier_exact,
       COUNT(*) AS customers
FROM raw_subscriptions
GROUP BY plan_tier_exact
ORDER BY plan_tier_exact;
-- Expect 6 rows: Basic 47, Plus 39, Premium 15, basic 1929, plus 1462, premium 708 ❌

SELECT COUNT(*) AS not_lowercase
FROM raw_subscriptions
WHERE plan_tier COLLATE utf8mb4_bin <> LOWER(plan_tier) COLLATE utf8mb4_bin;
-- Expect: 101 ❌

-- CHECK 4: Does 'churned' agree with churn_date and cancel_reason?
SELECT churned,
       COUNT(*)             AS customers,
       COUNT(churn_date)    AS has_churn_date,
       COUNT(cancel_reason) AS has_cancel_reason
FROM raw_subscriptions
GROUP BY churned;
-- Expect: yes = 1768 / 1768 / 1386 (382 churned with no reason ❌), no = 2432 / 0 / 0

-- CHECK 5: Price list by tier and plan type
SELECT LOWER(plan_tier) AS tier, plan_type, monthly_price, COUNT(*) AS customers
FROM raw_subscriptions
GROUP BY 1, 2, 3
ORDER BY 1, 2;
-- Expect: annual = 25% cheaper (basic 12.99 monthly vs 9.74 annual)

-- CHECK 6: Date range
SELECT MIN(signup_date) AS first_signup, MAX(signup_date) AS last_signup,
       MIN(churn_date)  AS first_churn,  MAX(churn_date)  AS last_churn
FROM raw_subscriptions;
-- Expect: 2024-07-01 / 2025-10-30 / 2024-07-02 / 2025-12-31

-- CHECK 7: Duplicate customer-months in usage
SELECT COUNT(*) AS duplicated_customer_months
FROM (SELECT customer_id, month
      FROM raw_usage
      GROUP BY customer_id, month
      HAVING COUNT(*) > 1) d;
-- Expect: 160 ❌

-- CHECK 8: Missing minutes
SELECT SUM(minutes_active IS NULL) AS null_minutes FROM raw_usage;
-- Expect: 506 ❌

-- CHECK 9: Outliers
SELECT ROUND(AVG(workouts_completed), 2) AS avg_workouts,
       MAX(workouts_completed)           AS max_workouts,
       MAX(minutes_active)               AS max_minutes
FROM raw_usage;
-- Expect: avg ~4.46, max 48, max 1653 ⚠️

-- CHECK 10: Orphan usage rows
SELECT COUNT(*) AS orphan_rows
FROM raw_usage u
LEFT JOIN raw_subscriptions s ON s.customer_id = u.customer_id
WHERE s.customer_id IS NULL;
-- Expect: 0 ✅