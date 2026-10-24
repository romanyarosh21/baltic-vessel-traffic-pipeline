CREATE TABLE IF NOT EXISTS raw.ais_messages (
    ts                      text,
    type_of_mobile          text,
    mmsi                    text,
    latitude                text,
    longitude               text,
    navigational_status     text,
    rot                     text,
    sog                     text,
    cog                     text,
    heading                 text,
    imo                     text,
    callsign                text,
    vessel_name             text,
    ship_type               text,
    cargo_type              text,
    width                   text,
    length                  text,
    position_fixing_device  text,
    draught                 text,
    destination             text,
    eta                     text,
    data_source_type        text,
    size_a                  text,
    size_b                  text,
    size_c                  text,
    size_d                  text,
    source_file             text        NOT NULL,
    loaded_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ais_messages_source_file_idx
    ON raw.ais_messages (source_file);