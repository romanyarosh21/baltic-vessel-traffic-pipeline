{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'ais_messages') }}
    where type_of_mobile in ('Class A', 'Class B')
      and mmsi ~ '^[0-9]{9}$'

),

typed as (

    select
        to_timestamp(ts, 'DD/MM/YYYY HH24:MI:SS')::timestamp as message_ts,
        mmsi,
        type_of_mobile                               as vessel_class,
        {{ safe_numeric('latitude') }}               as latitude,
        {{ safe_numeric('longitude') }}              as longitude,
        {{ safe_numeric('sog') }}                    as sog,
        {{ safe_numeric('cog') }}                    as cog,
        {{ safe_numeric('heading') }}::integer       as heading,
        nullif(navigational_status, 'Unknown value') as navigational_status,
        nullif(imo, 'Unknown')                       as imo,
        vessel_name,
        nullif(ship_type, 'Undefined')               as ship_type,
        {{ safe_numeric('length') }}                 as length_m,
        {{ safe_numeric('width') }}                  as width_m,
        {{ safe_numeric('draught') }}                as draught_m,
        nullif(destination, 'Unknown')               as destination,
        source_file
    from source

),

filtered as (

    select * from typed
    where latitude between -90 and 90
      and longitude between -180 and 180

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by mmsi, message_ts
            order by latitude, longitude
        ) as row_num
    from filtered

)

select
    message_ts, mmsi, vessel_class, latitude, longitude, sog, cog, heading,
    navigational_status, imo, vessel_name, ship_type,
    length_m, width_m, draught_m, destination, source_file
from deduplicated
where row_num = 1