-- Fails if a stop ends before it starts or has a negative duration
select *
from {{ ref('fct_vessel_stops') }}
where stop_end_ts < stop_start_ts
   or duration_minutes < 0