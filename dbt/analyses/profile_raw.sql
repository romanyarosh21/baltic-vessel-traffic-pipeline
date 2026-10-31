-- 1. Timestamps that do not match DD/MM/YYYY HH24:MI:SS
SELECT count(*) AS bad_ts_format
FROM raw.ais_messages
WHERE ts !~ '^[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}$';

-- 2. Navigational status values among vessels
SELECT navigational_status, count(*) AS n
FROM raw.ais_messages
WHERE type_of_mobile IN ('Class A', 'Class B')
GROUP BY 1
ORDER BY 2 DESC;

-- 3. MMSI that is not exactly 9 digits, among vessels
SELECT type_of_mobile, count(*) AS rows_with_bad_mmsi
FROM raw.ais_messages
WHERE type_of_mobile IN ('Class A', 'Class B')
  AND mmsi !~ '^[0-9]{9}$'
GROUP BY 1;

-- 4. Coordinates among vessels: missing, wrong format, out of range
SELECT
    count(*) FILTER (WHERE latitude IS NULL OR longitude IS NULL) AS null_coords,
    count(*) FILTER (WHERE latitude !~ '^-?[0-9]+(\.[0-9]+)?$'
                        OR longitude !~ '^-?[0-9]+(\.[0-9]+)?$') AS bad_format,
    count(*) FILTER (WHERE
        CASE WHEN latitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN latitude::numeric END NOT BETWEEN -90 AND 90
        OR CASE WHEN longitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN longitude::numeric END NOT BETWEEN -180 AND 180
    ) AS out_of_range
FROM raw.ais_messages
WHERE type_of_mobile IN ('Class A', 'Class B');

-- 5. Duplicated (mmsi, timestamp) pairs among vessels
SELECT count(*) AS duplicated_keys, sum(n - 1) AS surplus_rows
FROM (
    SELECT mmsi, ts, count(*) AS n
    FROM raw.ais_messages
    WHERE type_of_mobile IN ('Class A', 'Class B')
    GROUP BY 1, 2
    HAVING count(*) > 1
) d;