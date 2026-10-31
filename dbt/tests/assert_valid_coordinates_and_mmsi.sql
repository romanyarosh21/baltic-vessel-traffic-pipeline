-- Fails if any row has an out-of-range coordinate or a malformed MMSI
select *
from {{ ref('stg_ais_positions') }}
where latitude not between -90 and 90
   or longitude not between -180 and 180
   or mmsi !~ '^[0-9]{9}$'