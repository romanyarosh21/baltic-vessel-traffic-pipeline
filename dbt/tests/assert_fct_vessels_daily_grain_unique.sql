-- Fails if a (day, class, ship type) combination appears more than once
select activity_date, vessel_class, ship_type, count(*) as n
from {{ ref('fct_vessels_daily') }}
group by 1, 2, 3
having count(*) > 1