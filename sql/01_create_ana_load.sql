SHOW DATABASES;
-- Create the project database
DROP DATABASE IF EXISTS churn_db;
CREATE DATABASE churn_db;
USE churn_db;

-- RAW table 1: one row per customer
CREATE TABLE raw_subscriptions (
    customer_id         INT,
    signup_date         DATE,
    plan_type           VARCHAR(20),
    plan_tier           VARCHAR(20),
    monthly_price       DECIMAL(6,2),
    acquisition_channel VARCHAR(30),
    primary_device      VARCHAR(20),
    age_group           VARCHAR(10),
    churned             VARCHAR(3),
    churn_date          DATE NULL,
    cancel_reason       VARCHAR(40) NULL
);

-- RAW table 2: one row per customer per month
CREATE TABLE raw_usage (
    customer_id        INT,
    month              VARCHAR(7),
    workouts_completed INT,
    minutes_active     DECIMAL(8,1) NULL,
    classes_booked     INT,
    support_tickets    INT
);

-- Allow loading CSV files from your computer
SET GLOBAL local_infile = 1;