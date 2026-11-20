{{ config(materialized='table') }}

{% set max_silence_hours = var('stop_max_silence_hours', 12) %}

-- One row per stop: an uninterrupted run of messages from one Class A vessel
-- reporting the same stationary status (Moored or At anchor). A run also
-- ends when the vessel is silent for longer than the threshold.
with msgs as (

    select mmsi, message_ts, latitude, longitude, navigational_status
    from {{ ref('stg_ais_positions') }}
    where vessel_class = 'Class A'

),

marked as (

    select
        *,
        lag(navigational_status) over w as prev_status,
        lag(message_ts)          over w as prev_ts
    from msgs
    window w as (partition by mmsi order by message_ts)

),

runs as (

    select
        *,
        sum(case
                when navigational_status is distinct from prev_status
                  or message_ts - prev_ts > interval '1 hour' * {{ max_silence_hours }}
                then 1 else 0
            end) over (partition by mmsi order by message_ts) as run_id
    from marked

)

select
    mmsi,
    navigational_status                                                   as stop_status,
    min(message_ts)                                                       as stop_start_ts,
    max(message_ts)                                                       as stop_end_ts,
    round(extract(epoch from max(message_ts) - min(message_ts)) / 60)::int as duration_minutes,
    count(*)                                                              as messages,
    round(avg(latitude), 5)                                               as avg_lat,
    round(avg(longitude), 5)                                              as avg_lon
from runs
where navigational_status in ('Moored', 'At anchor')
group by mmsi, run_id, navigational_status
having count(*) >= 2