{{ config(materialized='table') }}

-- Each stop is assigned to the nearest port whose radius contains the stop's
-- average position. Stops outside every radius keep port_id = NULL.
select
    s.*,
    p.port_id,
    p.port_name,
    p.country
from {{ ref('fct_vessel_stops') }} as s
left join lateral (
    select pt.port_id, pt.port_name, pt.country
    from {{ ref('ports') }} as pt
    where st_dwithin(
        st_setsrid(st_makepoint(s.avg_lon::float8, s.avg_lat::float8), 4326)::geography,
        st_setsrid(st_makepoint(pt.lon::float8, pt.lat::float8), 4326)::geography,
        pt.radius_km * 1000
    )
    order by st_distance(
        st_setsrid(st_makepoint(s.avg_lon::float8, s.avg_lat::float8), 4326)::geography,
        st_setsrid(st_makepoint(pt.lon::float8, pt.lat::float8), 4326)::geography
    )
    limit 1
) as p on true