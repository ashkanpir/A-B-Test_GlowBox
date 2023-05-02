--With this first query, I calculate the number of users in each group and their conversion rates.

WITH 
avg_spent AS (
    SELECT group_name, AVG(spent) AS avg_spent
    FROM groups g
    JOIN activity a ON g.uid = a.uid
    GROUP BY group_name
),
conversion_rate AS (
    SELECT 
      g.group_name,
      COUNT(DISTINCT g.uid) AS num_users,
      COUNT(DISTINCT CASE WHEN COALESCE(a.spent, 0) > 0 THEN a.uid END) AS num_purchased,
      ROUND((COUNT(DISTINCT CASE WHEN COALESCE(a.spent, 0) > 0 THEN a.uid END) / COUNT(DISTINCT g.uid)::numeric), 5)
      AS conversion_rate_after
    FROM groups g
    LEFT JOIN activity a ON a.uid = g.uid
    WHERE g.group_name = 'A' OR g.group_name = 'B'
    GROUP BY g.group_name
)
SELECT *
FROM avg_spent
JOIN conversion_rate ON avg_spent.group_name = conversion_rate.group_name;
/*
The result is:
Group_name	 num_users              conversion_rate              total_users
"A"		    955				0.03923			24343
"B"		    1139			0.04630			24600
As a result of the above, we can calculate the standard error as below:*/
SELECT SQRT((0.039*(1-0.039) + 0.046*(1-0.046)) / (24343 + 24600 - 2));

--Which returns: 0.00129 round to 5 decimals

--With this query, I am checking the start and end dates of our tables, just to make sure and avoid confusion.

SELECT 
  MIN(g.join_dt) AS min_join_dt,
  MAX(g.join_dt) AS max_join_dt,
  MIN(a.dt) AS min_activity_dt,
  MAX(a.dt) AS max_activity_dt
FROM groups g
JOIN activity a ON a.uid = g.uid;
/*
The result is:
min_join_date     max_join_dt      min_activity_date     max_activity_date
"2023-01-25"	"2023-02-06"	 "2023-01-25"	        "2023-02-06"
*/

--This query helps check the proper randomization of each group in all days the experiment was run.

SELECT 
  join_day, 
  COUNT(DISTINCT CASE WHEN group_name = 'A' THEN uid END) AS num_a_users, 
  COUNT(DISTINCT CASE WHEN group_name = 'B' THEN uid END) AS num_b_users 
FROM generate_series('2023-01-25'::date, '2023-02-06'::date, '1 day') AS join_day
LEFT JOIN groups g ON DATE_TRUNC('day', g.join_dt) = join_day
GROUP BY join_day;

/*
The result is:
"2023-01-25 00:00:00+01"	5733	5913
"2023-01-26 00:00:00+01"	4114	4156
"2023-01-27 00:00:00+01"	3062	2981
"2023-01-28 00:00:00+01"	2310	2233
"2023-01-29 00:00:00+01"	1765	1802
"2023-01-30 00:00:00+01"	1444	1450
"2023-01-31 00:00:00+01"	1187	1205
"2023-02-01 00:00:00+01"	983	1074
"2023-02-02 00:00:00+01"	927	876
"2023-02-03 00:00:00+01"	774	876
"2023-02-04 00:00:00+01"	743	725
"2023-02-05 00:00:00+01"	663	673
"2023-02-06 00:00:00+01"	638	636

The randomization seems to have been practically significant as the difference of each group is within, or less than 5 percent of total users on each day.
*/


--With this query, I am trying to gauge the effect of this new feature being tested.

WITH group_a AS (
  SELECT 
    COUNT(DISTINCT uid) AS num_users,
    COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN uid END) AS num_purchased
  FROM groups
  LEFT JOIN activity ON activity.uid = groups.uid
  WHERE group_name = 'A'
), 
group_b AS (
  SELECT 
    COUNT(DISTINCT uid) AS num_users,
    COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN uid END) AS num_purchased
  FROM groups
  LEFT JOIN activity ON activity.uid = groups.uid
  WHERE group_name = 'B'
)
SELECT 
  ABS((group_a.num_purchased::float / group_a.num_users::float) - (group_b.num_purchased::float / group_b.num_users::float)) AS effect_size,
  CASE
    WHEN (group_b.num_purchased::float / group_b.num_users::float) - (group_a.num_purchased::float / group_a.num_users::float) > 0.01 THEN 'Practically significant'
    ELSE 'Not practically significant'
  END AS practical_significance
FROM group_a, group_b;

/*The result is: 
0.0070698225796701555	"Not practically significant"
*/
--Regarding the above musings, we can further check and confirm the results using this query:

SELECT 
  b.group_name AS group_b, 
  a.group_name AS group_a, b.conversion_rate, a.conversion_rate,
  b.conversion_rate - a.conversion_rate AS diff_conversion_rate,
 (b.conversion_rate - a.conversion_rate) / 0.001289 AS z_score

FROM 
  (SELECT 
    group_name, 
    COUNT(DISTINCT groups.uid) AS num_users, 
    COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN groups.uid END) AS num_purchased, 
    ROUND(CAST(COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN groups.uid END)::FLOAT / 
			   COUNT(DISTINCT groups.uid) AS DECIMAL(10, 3)), 3) AS conversion_rate 
   FROM groups 
   LEFT JOIN activity ON groups.uid = activity.uid 
   WHERE group_name = 'A' 
   GROUP BY group_name) a 
INNER JOIN 
  (SELECT 
    group_name, 
    COUNT(DISTINCT groups.uid) AS num_users, 
    COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN groups.uid END) AS num_purchased, 
    ROUND(CAST(COUNT(DISTINCT CASE WHEN COALESCE(spent, 0) > 0 THEN groups.uid END)::FLOAT / 
			   COUNT(DISTINCT groups.uid) AS DECIMAL(10, 3)), 3) AS conversion_rate 
   FROM groups 
   LEFT JOIN activity ON groups.uid = activity.uid 
   WHERE group_name = 'B' 
   GROUP BY group_name) b 
ON a.group_name <> b.group_name;


 



--With this query, I am comparing the effect against a minimum desired effect of 1%

WITH conversion_rates AS (
  SELECT 
    g.group_name,
    COUNT(DISTINCT g.uid) AS num_users,
    COUNT(DISTINCT CASE WHEN COALESCE(a.spent, 0) > 0 THEN a.uid END) AS num_purchased,
    COUNT(DISTINCT CASE WHEN COALESCE(a.spent, 0) > 0 THEN a.uid END) / COUNT(DISTINCT g.uid)::float AS conversion_rate
  FROM groups g
  LEFT JOIN activity a ON a.uid = g.uid
  WHERE g.group_name = 'A' OR g.group_name = 'B'
  GROUP BY g.group_name
)
SELECT 
  abs(a.conversion_rate - b.conversion_rate) AS observed_effect_size,
  0.01 AS practical_significance_threshold,
  CASE 
    WHEN abs(a.conversion_rate - b.conversion_rate) > 0.01 THEN 'Practically significant'
    ELSE 'Not practically significant'
  END AS practical_significance
FROM conversion_rates a
CROSS JOIN conversion_rates b
WHERE a.group_name = 'A' AND b.group_name = 'B';
/*
The result is 

0.0070698225796701555	0.01	"Not practically significant"

It is my conclusion that the effect of 0.7% might not be worth launching the new feature.
 We may need to run the experiment with a bigger sample size, or for a longer time.

The practical significance of the difference between the conversion rates of the two groups
depends on the context and specific goals of the business. However,
a difference of 0.007 between the conversion rates of Group B and Group A,
with a confidence interval of [0.00455, 0.00945], suggests that Group B has a higher conversion rate than Group A.
Whether this difference is practically significant or not would depend on various factors such as the baseline conversion rate,
the cost of acquiring new customers, and the potential revenue generated by each group. 
Since the confidence interval includes zero the result is not statistically significant. */

(-0.00457, 0.00963)
