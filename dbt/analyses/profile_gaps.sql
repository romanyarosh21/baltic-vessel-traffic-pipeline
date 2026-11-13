with gaps as (
    select
        mmsi,
        extract(epoch from message_ts - lag(message_ts)
            over (partition by mmsi order by message_ts)) as gap_s
    from staging.stg_ais_positions
    where vessel_class = 'Class A'
      and message_ts >= '2026-10-21'
      and message_ts <  '2026-10-22'
)
select
    count(*) filter (where gap_s > 600)   as over_10min,
    count(*) filter (where gap_s > 1800)  as over_30min,
    count(*) filter (where gap_s > 3600)  as over_1h,
    count(*) filter (where gap_s > 10800) as over_3h,
    count(*) filter (where gap_s > 21600) as over_6h,
    count(distinct mmsi) filter (where gap_s > 3600) as vessels_over_1h,
    percentile_cont(0.5)  within group (order by gap_s) as median_s,
    percentile_cont(0.99) within group (order by gap_s) as p99_s
from gaps
where gap_s is not null;