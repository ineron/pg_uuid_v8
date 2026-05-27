-- PostgreSQL UUID v8 regression test

-- Load extension
CREATE EXTENSION pg_uuid_v8;

-- Basic extension loading test
SELECT extname FROM pg_extension WHERE extname = 'pg_uuid_v8';

-- Test steganographic UUID generation
SELECT uuid_stego_generate() IS NOT NULL;

-- Test that generated UUIDs look like version 4
WITH test_uuid AS (
  SELECT uuid_stego_generate() as u
)
SELECT
  -- Check version character (should be 4)
  substring(u::text from 15 for 1) = '4' as is_version_4,
  -- Check variant character (should be 8, 9, A, or B)
  substring(u::text from 20 for 1) IN ('8', '9', 'a', 'b') as is_correct_variant
FROM test_uuid;

-- Test seed functionality
SELECT uuid_stego_set_seed('test_seed_123');
SELECT uuid_stego_get_seed();

-- Test timestamp extraction
WITH test_data AS (
  SELECT uuid_stego_generate() as uuid1, uuid_stego_generate() as uuid2
)
SELECT
  uuid_stego_extract_timestamp(uuid1) > 0 as has_timestamp1,
  uuid_stego_extract_timestamp(uuid2) > 0 as has_timestamp2,
  uuid_stego_extract_timestamp(uuid2) >= uuid_stego_extract_timestamp(uuid1) as timestamp_order
FROM test_data;

-- Test comparison functions
WITH test_uuids AS (
  SELECT uuid_stego_generate() as u1, uuid_stego_generate() as u2
)
SELECT
  uuid_stego_compare(u1, u1) = 0 as self_equal,
  uuid_stego_compare(u1, u2) != 0 OR uuid_stego_compare(u2, u1) != 0 as different_comparison
FROM test_uuids;

-- Test operators
WITH test_uuids AS (
  SELECT uuid_stego_generate() as u1, uuid_stego_generate() as u2
)
SELECT
  CASE WHEN u1 = u2 THEN true
       WHEN uuid_stego_lt(u1, u2) THEN uuid_stego_gt(u2, u1)
       WHEN uuid_stego_gt(u1, u2) THEN uuid_stego_lt(u2, u1)
       ELSE false
  END as operators_consistent
FROM test_uuids;

-- Test with different seeds
SELECT uuid_stego_set_seed('seed1');
SELECT uuid_stego_get_seed() = 'seed1' as seed_set_correctly;

SELECT uuid_stego_set_seed('seed2');
SELECT uuid_stego_get_seed() = 'seed2' as seed_changed_correctly;

-- Reset to default seed
SELECT uuid_stego_set_seed('pg_iuuid_default_seed_2024');
SELECT uuid_stego_get_seed() = 'pg_iuuid_default_seed_2024' as seed_reset;

-- Test encryption mode functionality
SELECT '=== Testing encryption modes ===' as test_encryption;

-- Test default mode
SELECT uuid_stego_get_encryption_mode() = 'XOR' as default_mode_xor;

-- Test mode setting
SELECT uuid_stego_set_encryption_mode('AES128');
SELECT uuid_stego_get_encryption_mode() = 'AES128' as mode_set_aes128;

-- Test UUID generation with AES128
SELECT uuid_stego_generate() IS NOT NULL as aes128_generation;

-- Test timestamp extraction with AES128
WITH aes_test AS (
    SELECT uuid_stego_generate() as aes_uuid
)
SELECT uuid_stego_extract_timestamp(aes_uuid) > 0 as aes128_extraction
FROM aes_test;

-- Test AES256 mode
SELECT uuid_stego_set_encryption_mode('AES256');
SELECT uuid_stego_get_encryption_mode() = 'AES256' as mode_set_aes256;

-- Test UUID generation with AES256
SELECT uuid_stego_generate() IS NOT NULL as aes256_generation;

-- Reset to XOR mode for compatibility
SELECT uuid_stego_set_encryption_mode('XOR');
SELECT uuid_stego_get_encryption_mode() = 'XOR' as mode_reset_xor;

-- Test UUID v8 convenience aliases
SELECT '=== Testing UUID v8 aliases ===' as test_aliases;

-- Test uuid_v8_generate
SELECT uuid_v8_generate() IS NOT NULL as v8_generation;

-- Test uuid_v8_extract_timestamp
WITH v8_test AS (
    SELECT uuid_v8_generate() as v8_uuid
)
SELECT uuid_v8_extract_timestamp(v8_uuid) > 0 as v8_extraction
FROM v8_test;

-- Test uuid_v8_compare
WITH v8_compare AS (
    SELECT uuid_v8_generate() as u1, uuid_v8_generate() as u2
)
SELECT
    uuid_v8_compare(u1, u1) = 0 as v8_self_equal,
    uuid_v8_compare(u1, u2) != 0 OR uuid_v8_compare(u2, u1) != 0 as v8_different
FROM v8_compare;

-- Test uuid_v8 configuration functions
SELECT uuid_v8_set_seed('v8_test_seed');
SELECT uuid_v8_get_seed() = 'v8_test_seed' as v8_seed_test;

SELECT uuid_v8_set_encryption_mode('AES128');
SELECT uuid_v8_get_encryption_mode() = 'AES128' as v8_encryption_test;

-- Reset to defaults
SELECT uuid_v8_set_seed('uuid_v8_default_seed_2024');
SELECT uuid_v8_set_encryption_mode('XOR');