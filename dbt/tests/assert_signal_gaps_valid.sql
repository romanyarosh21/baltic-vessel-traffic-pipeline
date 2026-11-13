-- Fails if a gap ends before it starts or is shorter than the threshold
select *
from {{ ref('fct_signal_gaps') }}
where gap_end_ts <= gap_start_ts
   or gap_minutes < {{ var('signal_gap_minutes', 60) }}