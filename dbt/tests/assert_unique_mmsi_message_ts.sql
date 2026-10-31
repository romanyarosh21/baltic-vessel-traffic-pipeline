-- Fails if any (mmsi, message_ts) pair appears more than once
select mmsi, message_ts, count(*) as n
from {{ ref('stg_ais_positions') }}
group by mmsi, message_ts
having count(*) > 1