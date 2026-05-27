-- PostgreSQL UUID v8 extension SQL definition
-- pg_uuid_v8: Steganographic UUIDs with hidden timestamps for PostgreSQL

-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_uuid_v8" to load this file. \quit

-- UUID v8 Steganographic Functions
-- Generate UUID v8 that looks like v4 but contains hidden timestamp
CREATE OR REPLACE FUNCTION uuid_stego_generate() RETURNS uuid
  AS 'MODULE_PATHNAME', 'uuid_stego_generate'
  LANGUAGE C VOLATILE;

-- Extract hidden timestamp from steganographic UUID
CREATE OR REPLACE FUNCTION uuid_stego_extract_timestamp(uuid) RETURNS bigint
  AS 'MODULE_PATHNAME', 'uuid_stego_extract_timestamp'
  LANGUAGE C IMMUTABLE STRICT;

-- Compare steganographic UUIDs by hidden timestamp
CREATE OR REPLACE FUNCTION uuid_stego_compare(uuid, uuid) RETURNS integer
  AS 'MODULE_PATHNAME', 'uuid_stego_compare'
  LANGUAGE C IMMUTABLE STRICT;

-- Set the steganographic seed for encoding/decoding
CREATE OR REPLACE FUNCTION uuid_stego_set_seed(text) RETURNS void
  AS 'MODULE_PATHNAME', 'uuid_stego_set_seed'
  LANGUAGE C VOLATILE STRICT;

-- Get current steganographic seed
CREATE OR REPLACE FUNCTION uuid_stego_get_seed() RETURNS text
  AS 'MODULE_PATHNAME', 'uuid_stego_get_seed'
  LANGUAGE C STABLE;

-- Set encryption mode (XOR, AES128, AES256)
CREATE OR REPLACE FUNCTION uuid_stego_set_encryption_mode(text) RETURNS void
  AS $$
    SELECT set_config('uuid_v8.encryption_mode', $1, false);
  $$ LANGUAGE SQL VOLATILE STRICT;

-- Get current encryption mode
CREATE OR REPLACE FUNCTION uuid_stego_get_encryption_mode() RETURNS text
  AS $$
    SELECT current_setting('uuid_v8.encryption_mode', true);
  $$ LANGUAGE SQL STABLE;

-- Operator for steganographic UUID comparison
CREATE OR REPLACE FUNCTION uuid_stego_lt(uuid, uuid) RETURNS boolean
  AS 'MODULE_PATHNAME', 'uuid_stego_lt'
  LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION uuid_stego_le(uuid, uuid) RETURNS boolean
  AS 'MODULE_PATHNAME', 'uuid_stego_le'
  LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION uuid_stego_gt(uuid, uuid) RETURNS boolean
  AS 'MODULE_PATHNAME', 'uuid_stego_gt'
  LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION uuid_stego_ge(uuid, uuid) RETURNS boolean
  AS 'MODULE_PATHNAME', 'uuid_stego_ge'
  LANGUAGE C IMMUTABLE STRICT;

-- Create operator class for indexing by hidden timestamp
CREATE OPERATOR < (
  PROCEDURE = uuid_stego_lt,
  LEFTARG = uuid,
  RIGHTARG = uuid,
  COMMUTATOR = >,
  NEGATOR = >=
);

CREATE OPERATOR <= (
  PROCEDURE = uuid_stego_le,
  LEFTARG = uuid,
  RIGHTARG = uuid,
  COMMUTATOR = >=,
  NEGATOR = >
);

CREATE OPERATOR > (
  PROCEDURE = uuid_stego_gt,
  LEFTARG = uuid,
  RIGHTARG = uuid,
  COMMUTATOR = <,
  NEGATOR = <=
);

CREATE OPERATOR >= (
  PROCEDURE = uuid_stego_ge,
  LEFTARG = uuid,
  RIGHTARG = uuid,
  COMMUTATOR = <=,
  NEGATOR = <
);

-- Helper functions for timestamp conversion
CREATE OR REPLACE FUNCTION timestamp_to_stego_time(timestamp with time zone) RETURNS bigint
  AS $$
    SELECT (extract(epoch from $1) * 1000000)::bigint;
  $$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION timestamp_to_stego_time(timestamp without time zone) RETURNS bigint
  AS $$
    SELECT (extract(epoch from $1) * 1000000)::bigint;
  $$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION stego_time_to_timestamp(bigint) RETURNS timestamp with time zone
  AS $$
    SELECT to_timestamp($1 / 1000000.0);
  $$ LANGUAGE SQL IMMUTABLE STRICT;

-- Helper function to check if UUID was created in time range
CREATE OR REPLACE FUNCTION uuid_stego_in_range(uuid, timestamp with time zone, timestamp with time zone) RETURNS boolean
  AS $$
    SELECT uuid_stego_extract_timestamp($1) BETWEEN
           (extract(epoch from $2) * 1000000)::bigint AND
           (extract(epoch from $3) * 1000000)::bigint;
  $$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION uuid_stego_in_range(uuid, timestamp without time zone, timestamp without time zone) RETURNS boolean
  AS $$
    SELECT uuid_stego_extract_timestamp($1) BETWEEN
           (extract(epoch from $2) * 1000000)::bigint AND
           (extract(epoch from $3) * 1000000)::bigint;
  $$ LANGUAGE SQL IMMUTABLE STRICT;

-- UUID v8 Convenience Aliases
-- These provide clearer naming for the UUID v8 standard

CREATE OR REPLACE FUNCTION uuid_v8_generate() RETURNS uuid
  AS $$
    SELECT uuid_stego_generate();
  $$ LANGUAGE SQL VOLATILE;

CREATE OR REPLACE FUNCTION uuid_v8_extract_timestamp(uuid) RETURNS bigint
  AS $$
    SELECT uuid_stego_extract_timestamp($1);
  $$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION uuid_v8_compare(uuid, uuid) RETURNS integer
  AS $$
    SELECT uuid_stego_compare($1, $2);
  $$ LANGUAGE SQL IMMUTABLE STRICT;

-- UUID v8 Configuration Functions
CREATE OR REPLACE FUNCTION uuid_v8_set_seed(text) RETURNS void
  AS $$
    SELECT uuid_stego_set_seed($1);
  $$ LANGUAGE SQL VOLATILE STRICT;

CREATE OR REPLACE FUNCTION uuid_v8_get_seed() RETURNS text
  AS $$
    SELECT uuid_stego_get_seed();
  $$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION uuid_v8_set_encryption_mode(text) RETURNS void
  AS $$
    SELECT uuid_stego_set_encryption_mode($1);
  $$ LANGUAGE SQL VOLATILE STRICT;

CREATE OR REPLACE FUNCTION uuid_v8_get_encryption_mode() RETURNS text
  AS $$
    SELECT uuid_stego_get_encryption_mode();
  $$ LANGUAGE SQL STABLE;