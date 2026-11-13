{{ config(materialized='table') }}

{% set threshold_minutes = var('signal_gap_minutes', 60) %}

-- One row per pause longer than the threshold between two consecutive
-- messages of the same Class A vessel.
with ordered as (

    select
        mmsi,
        message_ts,
        latitude,
        longitude,
        lag(message_ts)          over w as prev_ts,
        lag(latitude)            over w as prev_lat,
        lag(longitude)           over w as prev_lon,
        lag(navigational_status) over w as prev_status
    from {{ ref('stg_ais_positions') }}
    where vessel_class = 'Class A'
    window w as (partition by mmsi order by message_ts)

)

select
    mmsi,
    prev_ts                                                   as gap_start_ts,
    message_ts                                                as gap_end_ts,
    round(extract(epoch from message_ts - prev_ts) / 60)::int as gap_minutes,
    prev_lat                                                  as start_lat,
    prev_lon                                                  as start_lon,
    latitude                                                  as end_lat,
    longitude                                                 as end_lon,
    prev_status                                               as status_before_gap,
    round((st_distance(
        st_setsrid(st_makepoint(prev_lon::float8, prev_lat::float8), 4326)::geography,
        st_setsrid(st_makepoint(longitude::float8, latitude::float8), 4326)::geography
    ) / 1000)::numeric, 1)                                    as distance_km
from ordered
where prev_ts is not null
  and message_ts - prev_ts > interval '1 minute' * {{ threshold_minutes }}