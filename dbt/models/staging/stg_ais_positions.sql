{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='source_file',
    on_schema_change='fail',
    indexes=[{'columns': ['source_file']}]
) }}

{# Decide which raw files to process BEFORE the main query runs, so Postgres
   reads only those files instead of scanning the whole raw table. #}
{% set new_files = [] %}
{% if execute %}
    {% set find_files %}
        select l.source_file
        from {{ source('raw', 'load_log') }} as l
        {% if is_incremental() %}
        left join (
            select source_file, max(source_loaded_at) as processed_at
            from {{ this }}
            group by source_file
        ) as p on p.source_file = l.source_file
        {% endif %}
        where l.status = 'complete'
        {% if is_incremental() %}
          and (p.source_file is null or p.processed_at < l.loaded_at)
        {% endif %}
        order by l.source_file
    {% endset %}
    {% for row in run_query(find_files).rows %}
        {% do new_files.append(row[0]) %}
    {% endfor %}
{% endif %}

{% set file_list %}
    {%- if new_files -%}
        {%- for f in new_files -%}'{{ f | replace("'", "''") }}'{{ ',' if not loop.last }}{%- endfor -%}
    {%- else -%}
        '__no_new_files__'
    {%- endif -%}
{% endset %}

with files_to_process as (

    select source_file, loaded_at
    from {{ source('raw', 'load_log') }}
    where source_file in ({{ file_list }})

),

source as (

    select m.*, f.loaded_at as source_loaded_at
    from {{ source('raw', 'ais_messages') }} as m
    inner join files_to_process as f on f.source_file = m.source_file
    -- repeated on purpose: lets Postgres use the source_file index on the raw table
    where m.source_file in ({{ file_list }})
      and m.type_of_mobile in ('Class A', 'Class B')
      and m.mmsi ~ '^[0-9]{9}$'

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
        source_file,
        source_loaded_at
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
    length_m, width_m, draught_m, destination, source_file, source_loaded_at
from deduplicated
where row_num = 1