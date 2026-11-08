{{ config(materialized='table') }}

-- One row per MMSI. Position messages usually carry no static data, so the
-- name, type and size come from the latest message that has any of them.
with seen as (

    select
        mmsi,
        max(vessel_class) as vessel_class,
        min(message_ts)   as first_seen,
        max(message_ts)   as last_seen,
        count(*)          as message_count
    from {{ ref('stg_ais_positions') }}
    group by mmsi

),

latest_static as (

    select distinct on (mmsi)
        mmsi, vessel_name, ship_type, length_m, width_m
    from {{ ref('stg_ais_positions') }}
    where vessel_name is not null or ship_type is not null
    order by mmsi, message_ts desc

)

select
    s.mmsi,
    s.vessel_class,
    l.vessel_name,
    l.ship_type,
    l.length_m,
    l.width_m,
    s.first_seen,
    s.last_seen,
    s.message_count
from seen as s
left join latest_static as l on l.mmsi = s.mmsi