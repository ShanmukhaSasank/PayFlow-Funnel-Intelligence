CREATE TABLE fintech_funnel_events (
    event_id        VARCHAR(20),
    user_id         VARCHAR(10),
    session_id      VARCHAR(10),
    event_name      VARCHAR(30),
    event_timestamp TIMESTAMP,
    device_type     VARCHAR(10),
    user_segment    VARCHAR(20),
    payment_type    VARCHAR(20),
    amount          NUMERIC(10,2)
);

DROP TABLE fintech_funnel_events;

CREATE TABLE fintech_funnel_events (
    session_id      VARCHAR(20),
    user_id         VARCHAR(20),
    event           VARCHAR(30),
    event_status    VARCHAR(20),
    timestamp       TIMESTAMP,
    device          VARCHAR(10),
    segment         VARCHAR(20),
    city            VARCHAR(30),
    age             INT,
    payment_type    VARCHAR(20),
    amount          NUMERIC(10,2),
    reached_success INT
);

SELECT event, COUNT(*) AS event_count
FROM fintech_funnel_events
GROUP BY event
ORDER BY event_count DESC;

/*Query 1 — Funnel Stage Counts*/
SELECT 
    event,
    COUNT(DISTINCT session_id) AS session_count
FROM fintech_funnel_events
GROUP BY event
ORDER BY session_count DESC;

/*Query 2 — Stage-wise Conversion Rate
This shows the % of users who proceed from one stage to the next.*/
WITH stage_counts AS (
    SELECT 
        event,
        COUNT(DISTINCT session_id) AS session_count
    FROM fintech_funnel_events
    GROUP BY event
),
ordered_stages AS (
    SELECT 
        event,
        session_count,
        LAG(session_count) OVER (
            ORDER BY CASE event
                WHEN 'app_open'          THEN 1
                WHEN 'login'             THEN 2
                WHEN 'home_screen'       THEN 3
                WHEN 'initiate_payment'  THEN 4
                WHEN 'enter_details'     THEN 5
                WHEN 'payment_processing'THEN 6
                WHEN 'payment_success'   THEN 7
            END
        ) AS prev_count
    FROM stage_counts
)
SELECT 
    event,
    session_count,
    prev_count,
    ROUND(session_count * 100.0 / prev_count, 2) AS conversion_rate_pct
FROM ordered_stages
ORDER BY CASE event
    WHEN 'app_open'           THEN 1
    WHEN 'login'              THEN 2
    WHEN 'home_screen'        THEN 3
    WHEN 'initiate_payment'   THEN 4
    WHEN 'enter_details'      THEN 5
    WHEN 'payment_processing' THEN 6
    WHEN 'payment_success'    THEN 7
END;

/*Query 3 — Overall Funnel Conversion Rate
How many users who opened the app actually completed a payment:*/
SELECT
    COUNT(DISTINCT CASE WHEN event = 'app_open' THEN session_id END) AS total_sessions,
    COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) AS successful_sessions,
    ROUND(
        COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) * 100.0 /
        COUNT(DISTINCT CASE WHEN event = 'app_open' THEN session_id END), 2
    ) AS overall_conversion_pct
FROM fintech_funnel_events;

/*Query 4 — Drop-off Count Per Stage*/
WITH stage_counts AS (
    SELECT 
        event,
        COUNT(DISTINCT session_id) AS session_count
    FROM fintech_funnel_events
    GROUP BY event
),
ordered_stages AS (
    SELECT 
        event,
        session_count,
        LAG(session_count) OVER (
            ORDER BY CASE event
                WHEN 'app_open'           THEN 1
                WHEN 'login'              THEN 2
                WHEN 'home_screen'        THEN 3
                WHEN 'initiate_payment'   THEN 4
                WHEN 'enter_details'      THEN 5
                WHEN 'payment_processing' THEN 6
                WHEN 'payment_success'    THEN 7
            END
        ) AS prev_count
    FROM stage_counts
)
SELECT 
    event,
    session_count,
    COALESCE(prev_count - session_count, 0) AS dropped_users
FROM ordered_stages
ORDER BY CASE event
    WHEN 'app_open'           THEN 1
    WHEN 'login'              THEN 2
    WHEN 'home_screen'        THEN 3
    WHEN 'initiate_payment'   THEN 4
    WHEN 'enter_details'      THEN 5
    WHEN 'payment_processing' THEN 6
    WHEN 'payment_success'    THEN 7
END;

/*Query 5 — Segment-wise Conversion Rate*/
SELECT 
    segment,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) AS successful_sessions,
    ROUND(
        COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) * 100.0 /
        COUNT(DISTINCT session_id), 2
    ) AS conversion_rate_pct
FROM fintech_funnel_events
GROUP BY segment
ORDER BY conversion_rate_pct DESC;

/*Query 6 — Device-wise Conversion Rate*/
SELECT 
    device,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) AS successful_sessions,
    ROUND(
        COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) * 100.0 /
        COUNT(DISTINCT session_id), 2
    ) AS conversion_rate_pct
FROM fintech_funnel_events
GROUP BY device
ORDER BY conversion_rate_pct DESC;

/*Query 7 — Payment Type Distribution Among Successful Payments*/
SELECT 
    payment_type,
    COUNT(DISTINCT session_id) AS successful_sessions,
    ROUND(
        COUNT(DISTINCT session_id) * 100.0 /
        SUM(COUNT(DISTINCT session_id)) OVER (), 2
    ) AS share_pct
FROM fintech_funnel_events
WHERE event = 'payment_success'
GROUP BY payment_type
ORDER BY successful_sessions DESC;

/*Query 8 — Avg Time-to-Conversion Per Stage (in seconds)*/
WITH stage_times AS (
    SELECT
        session_id,
        event,
        timestamp,
        LAG(timestamp) OVER (
            PARTITION BY session_id
            ORDER BY CASE event
                WHEN 'app_open'           THEN 1
                WHEN 'login'              THEN 2
                WHEN 'home_screen'        THEN 3
                WHEN 'initiate_payment'   THEN 4
                WHEN 'enter_details'      THEN 5
                WHEN 'payment_processing' THEN 6
                WHEN 'payment_success'    THEN 7
            END
        ) AS prev_timestamp
    FROM fintech_funnel_events
)
SELECT
    event,
    ROUND(AVG(EXTRACT(EPOCH FROM (timestamp - prev_timestamp))), 2) AS avg_seconds_from_prev_stage
FROM stage_times
WHERE prev_timestamp IS NOT NULL
GROUP BY event
ORDER BY CASE event
    WHEN 'login'              THEN 2
    WHEN 'home_screen'        THEN 3
    WHEN 'initiate_payment'   THEN 4
    WHEN 'enter_details'      THEN 5
    WHEN 'payment_processing' THEN 6
    WHEN 'payment_success'    THEN 7
END;

/*Query 9 — Fast vs Slow Converters*/
WITH session_duration AS (
    SELECT
        session_id,
        MIN(timestamp) AS session_start,
        MAX(timestamp) AS session_end,
        EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) AS duration_seconds,
        MAX(CASE WHEN event = 'payment_success' THEN 1 ELSE 0 END) AS converted
    FROM fintech_funnel_events
    GROUP BY session_id
)
SELECT
    CASE 
        WHEN duration_seconds <= 120 THEN 'Fast (≤2 min)'
        WHEN duration_seconds <= 300 THEN 'Medium (2-5 min)'
        ELSE 'Slow (>5 min)'
    END AS converter_type,
    COUNT(session_id) AS total_sessions,
    SUM(converted) AS successful_payments,
    ROUND(SUM(converted) * 100.0 / COUNT(session_id), 2) AS conversion_rate_pct
FROM session_duration
GROUP BY converter_type
ORDER BY conversion_rate_pct DESC;

/*Query 10 — Top 10 Cities by Payment Success*/
SELECT 
    city,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) AS successful_payments,
    ROUND(
        COUNT(DISTINCT CASE WHEN event = 'payment_success' THEN session_id END) * 100.0 /
        COUNT(DISTINCT session_id), 2
    ) AS conversion_rate_pct
FROM fintech_funnel_events
GROUP BY city
ORDER BY successful_payments DESC
LIMIT 10;