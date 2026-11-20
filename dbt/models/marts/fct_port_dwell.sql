{{ config(materialized='table') }}

-- Dwell time per port or anchorage: one row per place with at least one stop.
-- Stops at the edges of the loaded period are truncated.
select
    port_id,
    port_name,
    country,
    place_type,
    count(*)                                                    as stops,
    count(distinct mmsi)                                        as vessels,
    round((percentile_cont(0.5) within group (order by duration_minutes) / 60)::numeric, 1) as median_hours,
    round((avg(duration_minutes) / 60)::numeric, 1)             as avg_hours,
    round((percentile_cont(0.9) within group (order by duration_minutes) / 60)::numeric, 1) as p90_hours,
    round(100.0 * count(*) filter (where duration_minutes >= 1440) / count(*), 1) as pct_over_24h
from {{ ref('fct_port_stops') }}
where port_id is not null
group by 1, 2, 3, 4