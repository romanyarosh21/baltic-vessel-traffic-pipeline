-- A. What are the out-of-range coordinates?
SELECT latitude, longitude, count(*) AS n
FROM raw.ais_messages
WHERE type_of_mobile IN ('Class A', 'Class B')
  AND (
    CASE WHEN latitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN latitude::numeric END NOT BETWEEN -90 AND 90
    OR CASE WHEN longitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN longitude::numeric END NOT BETWEEN -180 AND 180
  )
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 5;

-- B. What do the non-9-digit MMSI look like?
SELECT mmsi, type_of_mobile, count(*) AS n
FROM raw.ais_messages
WHERE type_of_mobile IN ('Class A', 'Class B')
  AND mmsi !~ '^[0-9]{9}$'
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 5;

-- C. Are duplicates exact copies or different positions?
SELECT
    count(*) AS duplicated_keys,
    count(*) FILTER (WHERE positions = 1) AS same_position,
    count(*) FILTER (WHERE positions > 1) AS different_positions
FROM (
    SELECT mmsi, ts, count(DISTINCT (latitude, longitude)) AS positions
    FROM raw.ais_messages
    WHERE type_of_mobile IN ('Class A', 'Class B')
    GROUP BY mmsi, ts
    HAVING count(*) > 1
) d;

-- D. One duplicated key, side by side
WITH one AS (
    SELECT mmsi, ts
    FROM raw.ais_messages
    WHERE type_of_mobile = 'Class A'
    GROUP BY mmsi, ts
    HAVING count(*) > 1
    LIMIT 1
)
SELECT r.ts, r.mmsi, r.latitude, r.longitude, r.sog, r.cog, r.heading,
       r.navigational_status, r.vessel_name, r.destination
FROM raw.ais_messages r
JOIN one o ON o.mmsi = r.mmsi AND o.ts = r.ts
WHERE r.type_of_mobile = 'Class A';