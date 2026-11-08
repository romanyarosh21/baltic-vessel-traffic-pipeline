{{ config(materialized='table') }}

-- Grain: one row per day x vessel class x ship type.
select
    s.message_ts::date                as activity_date,
    s.vessel_class,
    coalesce(d.ship_type, 'Unknown')  as ship_type,
    count(distinct s.mmsi)            as vessels,
    count(*)                          as messages
from {{ ref('stg_ais_positions') }} as s
left join {{ ref('dim_vessels') }} as d on d.mmsi = s.mmsi
group by 1, 2, 3