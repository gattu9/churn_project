USE churn_db;

CREATE OR REPLACE VIEW vw_customer_summary AS
SELECT c.*,
       e.months_active,
       ROUND(e.avg_workouts, 2) AS avg_workouts,
       ROUND(e.avg_minutes, 1)  AS avg_minutes,
       e.total_classes,
       e.total_tickets,
       CASE WHEN e.avg_workouts < 2 THEN '1. Low'
            WHEN e.avg_workouts < 5 THEN '2. Medium'
            ELSE '3. High' END AS engagement_level
FROM customers c
LEFT JOIN (
    SELECT customer_id,
           COUNT(*)                AS months_active,
           AVG(workouts_completed) AS avg_workouts,
           AVG(minutes_active)     AS avg_minutes,
           SUM(classes_booked)     AS total_classes,
           SUM(support_tickets)    AS total_tickets
    FROM monthly_usage
    GROUP BY customer_id
) e ON e.customer_id = c.customer_id;

CREATE OR REPLACE VIEW vw_monthly_usage AS
SELECT u.*,
       ROW_NUMBER() OVER (PARTITION BY u.customer_id
                          ORDER BY u.usage_month DESC) AS months_before_end
FROM monthly_usage u;

SELECT COUNT(*) FROM vw_customer_summary;   -- Expect 4200
SELECT COUNT(*) FROM vw_monthly_usage;      -- Expect 30525