/* =========================================================
   04_analysis.sql
   Customer Churn Analysis - business questions
   ========================================================= */
USE churn_db;

-- Q1. Overall churn rate and revenue impact
SELECT COUNT(*)                                             AS total_customers,
       SUM(is_churned)                                      AS churned_customers,
       ROUND(100 * AVG(is_churned), 1)                      AS churn_rate_pct,
       SUM(CASE WHEN is_churned = 0 THEN monthly_price END) AS active_mrr,
       SUM(CASE WHEN is_churned = 1 THEN monthly_price END) AS lost_mrr,
       ROUND(AVG(monthly_price), 2)                         AS avg_price
FROM customers;
-- Expect: 4200 | 1768 | 42.1 | 39494.43 | 30822.07 | 16.74

-- Q2. Churn by plan type (monthly vs annual)
SELECT plan_type,
       COUNT(*)                        AS customers,
       SUM(is_churned)                 AS churned,
       ROUND(100 * AVG(is_churned), 1) AS churn_rate_pct
FROM customers
GROUP BY plan_type
ORDER BY churn_rate_pct DESC;
-- Expect: monthly 51.2 | annual 26.4  -> monthly churns ~2x more

-- Q3. Plan type x tier
SELECT plan_type, plan_tier,
       COUNT(*)                        AS customers,
       ROUND(100 * AVG(is_churned), 1) AS churn_rate_pct
FROM customers
GROUP BY plan_type, plan_tier
ORDER BY churn_rate_pct DESC;
-- Expect: all monthly ~51-53%, all annual ~25-27% -> tier barely matters

-- Q4. Acquisition channel, ranked
SELECT acquisition_channel,
       COUNT(*)                                    AS customers,
       ROUND(100 * AVG(is_churned), 1)             AS churn_rate_pct,
       RANK() OVER (ORDER BY AVG(is_churned) DESC) AS churn_rank
FROM customers
GROUP BY acquisition_channel
ORDER BY churn_rank;
-- Expect: promo_offer 50.8, partner 42.9, organic 41.0, paid_social 38.9, referral 33.8

-- Q5a. Device
SELECT primary_device, COUNT(*) AS customers,
       ROUND(100 * AVG(is_churned), 1) AS churn_rate_pct
FROM customers
GROUP BY primary_device
ORDER BY churn_rate_pct DESC;
-- Expect: android 45.0, ios 40.4, web 40.4

-- Q5b. Age group
SELECT age_group, COUNT(*) AS customers,
       ROUND(100 * AVG(is_churned), 1) AS churn_rate_pct
FROM customers
GROUP BY age_group
ORDER BY age_group;
-- Expect: 18-24 42.8, 25-34 42.4, 35-44 42.0, 45-54 42.6, 55+ 38.9 -> little effect

-- Q6. Why do customers leave?
SELECT cancel_reason,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_churned
FROM customers
WHERE is_churned = 1
GROUP BY cancel_reason
ORDER BY customers DESC;
-- Expect: not_using_enough 32.2, not_provided 21.6, too_expensive 18.2,
--         found_alternative 9.9, other 9.2, technical_issues 8.9

-- Q7. Does engagement predict churn?
WITH engagement AS (
    SELECT customer_id, AVG(workouts_completed) AS avg_workouts
    FROM monthly_usage
    GROUP BY customer_id
)
SELECT CASE WHEN e.avg_workouts < 2 THEN '1. Low (<2/month)'
            WHEN e.avg_workouts < 5 THEN '2. Medium (2-5/month)'
            ELSE '3. High (5+/month)' END AS engagement_level,
       COUNT(*)                           AS customers,
       ROUND(100 * AVG(c.is_churned), 1)  AS churn_rate_pct
FROM engagement e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY engagement_level
ORDER BY engagement_level;
-- Expect: Low 59.9 | Medium 41.3 | High 24.9  <- strongest pattern in the data

-- Q8. Early warning: activity in the last 4 months of each customer's record
WITH ranked AS (
    SELECT u.customer_id, c.churn_status, u.workouts_completed,
           ROW_NUMBER() OVER (PARTITION BY u.customer_id
                              ORDER BY u.usage_month DESC) AS months_before_end,
           COUNT(*)     OVER (PARTITION BY u.customer_id)  AS months_of_data
    FROM monthly_usage u
    JOIN customers c ON c.customer_id = u.customer_id
)
SELECT churn_status, months_before_end,
       ROUND(AVG(workouts_completed), 2) AS avg_workouts
FROM ranked
WHERE months_before_end <= 4 AND months_of_data >= 4
GROUP BY churn_status, months_before_end
ORDER BY churn_status, months_before_end DESC;
-- Expect Churned: 3.01, 3.02, 2.90, 2.54 (drops in final months)
--        Active:  5.07, 4.97, 4.98, 4.71

-- Q9a. Do class bookers churn less?
WITH e AS (
    SELECT customer_id, AVG(classes_booked) AS avg_classes
    FROM monthly_usage GROUP BY customer_id
)
SELECT CASE WHEN e.avg_classes > 0 THEN 'Booked classes' ELSE 'Never booked' END AS class_user,
       COUNT(*) AS customers,
       ROUND(100 * AVG(c.is_churned), 1) AS churn_rate_pct
FROM e JOIN customers c USING (customer_id)
GROUP BY class_user;
-- Expect: Booked 39.3 | Never 44.6

-- Q9b. Do support tickets matter?
WITH e AS (
    SELECT customer_id, SUM(support_tickets) AS tickets
    FROM monthly_usage GROUP BY customer_id
)
SELECT CASE WHEN tickets = 0 THEN '0' WHEN tickets <= 2 THEN '1-2' ELSE '3+' END AS tickets_group,
       COUNT(*) AS customers,
       ROUND(100 * AVG(c.is_churned), 1) AS churn_rate_pct
FROM e JOIN customers c USING (customer_id)
GROUP BY tickets_group
ORDER BY tickets_group;
-- Expect: 0 42.8 | 1-2 42.1 | 3+ 38.3 -> no real link (a finding in itself)

-- Q10a. How long do churners stay?
SELECT ROUND(AVG(tenure_days)) AS avg_days_before_churn
FROM customers WHERE is_churned = 1;
-- Expect: ~156 days

-- Q10b. Churned customers per month + running total
SELECT churn_month, churned,
       SUM(churned) OVER (ORDER BY churn_month) AS running_total
FROM (SELECT DATE_FORMAT(churn_date, '%Y-%m') AS churn_month, COUNT(*) AS churned
      FROM customers
      WHERE is_churned = 1
      GROUP BY churn_month) m
ORDER BY churn_month;
-- Expect: rising counts; running total ends at 1768

-- Q11. Active customers at risk now (monthly plan + low recent activity)
WITH recent AS (
    SELECT customer_id, AVG(workouts_completed) AS avg_last_2_months
    FROM (SELECT u.*, ROW_NUMBER() OVER (PARTITION BY customer_id
                                         ORDER BY usage_month DESC) AS rn
          FROM monthly_usage u) x
    WHERE rn <= 2
    GROUP BY customer_id
)
SELECT c.customer_id, c.plan_type, c.plan_tier, c.acquisition_channel,
       c.monthly_price, ROUND(r.avg_last_2_months, 1) AS recent_workouts
FROM customers c
JOIN recent r ON r.customer_id = c.customer_id
WHERE c.is_churned = 0
  AND c.plan_type = 'monthly'
  AND r.avg_last_2_months < 2
ORDER BY c.monthly_price DESC;
-- A target list for a retention campaignSs