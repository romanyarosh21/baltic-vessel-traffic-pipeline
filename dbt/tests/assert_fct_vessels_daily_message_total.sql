-- Fails if the daily table loses or duplicates messages compared to staging
select f.total_messages, s.total_rows
from (select sum(messages) as total_messages from {{ ref('fct_vessels_daily') }}) as f
cross join (select count(*) as total_rows from {{ ref('stg_ais_positions') }}) as s
where f.total_messages <> s.total_rows