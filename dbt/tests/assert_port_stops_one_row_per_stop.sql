-- Fails if the port assignment changed the number of stops (join duplicated or lost rows)
select a.stops_with_port, b.stops
from (select count(*) as stops_with_port from {{ ref('fct_port_stops') }}) as a
cross join (select count(*) as stops from {{ ref('fct_vessel_stops') }}) as b
where a.stops_with_port <> b.stops