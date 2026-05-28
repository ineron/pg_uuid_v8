# pg_uuid_v8

A PostgreSQL extension for steganographic UUIDs with embedded timestamps.

[![PGXN version](https://badge.fury.io/pg/pg_uuid_v8.svg)](https://pgxn.org/dist/pg_uuid_v8/)
[![PostgreSQL 12+](https://img.shields.io/badge/PostgreSQL-12%2B-blue.svg)](https://www.postgresql.org/)

## Overview

`pg_uuid_v8` addresses the performance vs privacy trade-off in UUID usage by implementing steganographic UUIDs. These UUIDs maintain full compatibility with the UUID v4 format while embedding hidden timestamps that enable efficient indexing and range queries.

## Features

- **UUID v4 Compatibility**: Generated UUIDs pass standard v4 validation (correct version and variant bits)
- **Hidden Timestamps**: Microsecond-precision timestamps embedded using steganographic techniques
- **Configurable Encryption**: XOR, AES-128, and AES-256 modes for timestamp obfuscation
- **Functional Indexing**: Support for PostgreSQL functional indexes on extracted timestamps  
- **Range Queries**: Efficient time-based queries using hidden timestamp data
- **Seed Management**: Configurable encryption seeds via PostgreSQL GUC variables

## Technical Approach

Standard UUID implementations present a trade-off between indexing performance and timestamp privacy:

- **UUID v4**: Random values provide good privacy but result in poor B-tree index performance due to random insertion patterns
- **UUID v7**: Timestamp-based prefixes enable efficient indexing but expose creation time information

This extension implements steganographic UUIDs that:
- Maintain UUID v4 format compliance (version=4, proper variant bits)
- Embed encrypted timestamps in the random portion of the UUID
- Support functional indexing on extracted timestamps for efficient range queries
- Provide configurable encryption to prevent timestamp discovery

## Installation

### Option 1: Install from PGXN (Recommended)

The extension is available on the PostgreSQL Extension Network (PGXN):

```bash
# Install PGXN client if not already installed
# Ubuntu/Debian: sudo apt install pgxnclient
# RHEL/CentOS: sudo dnf install pgxnclient  
# Or: pip install pgxnclient

# Install pg_uuid_v8 extension
pgxn install pg_uuid_v8

# Create extension in your database
psql -d your_database -c "CREATE EXTENSION pg_uuid_v8;"
```

### Option 2: Build from Source

For development or if PGXN is not available:

```bash
# Install dependencies (OpenSSL required)
sudo dnf install openssl-devel postgresql-devel  # RHEL/CentOS
# sudo apt install libssl-dev postgresql-server-dev-all  # Ubuntu/Debian

# Build the extension
make

# Install (requires PostgreSQL development headers)
sudo make install

# Note: You may see LLVM-related errors during installation like:
# "/usr/lib64/llvm20/bin/llvm-lto: No such file or directory"
# This is not critical - the extension will work correctly without LLVM JIT

# Verify installation succeeded by checking key files
ls /usr/pgsql-*/lib/pg_uuid_v8.so /usr/pgsql-*/share/extension/pg_uuid_v8*

# Run regression tests
make installcheck
```

### Troubleshooting Installation

**LLVM bitcode errors**: During `make install` you may see errors about missing `llvm-lto`. This is **not critical** - the extension works without LLVM JIT compilation. The important files that must be installed are:
- `pg_uuid_v8.so` (shared library)
- `pg_uuid_v8.control` (extension metadata)  
- `pg_uuid_v8--1.0.sql` (SQL definitions)

**Alternative installation** (if make install fails completely):
```bash
# Install files manually
sudo cp pg_uuid_v8.so $(pg_config --pkglibdir)/
sudo cp pg_uuid_v8.control pg_uuid_v8--1.0.sql $(pg_config --sharedir)/extension/
```

## Usage

### Basic UUID v8 Generation

```sql
-- Create the PostgreSQL UUID v8 extension in your database
CREATE EXTENSION pg_uuid_v8;

-- Option 1: Use uuid_v8 convenience functions
SELECT uuid_v8_generate();
-- Result: bf3fcf45-9476-4138-bf48-03933d90dc2d (looks like UUID v4!)

-- Option 2: Use steganographic functions (same functionality)  
SELECT uuid_stego_generate();

-- Set your secret seed (important for security!)
SELECT uuid_v8_set_seed('your_secret_seed_here');

-- Extract hidden timestamp (microseconds since Unix epoch)
SELECT uuid_stego_extract_timestamp('bf3fcf45-9476-4138-bf48-03933d90dc2d');
-- Result: 91026979719220

-- Sort by hidden timestamp for efficient indexing
CREATE TABLE events (
    id uuid PRIMARY KEY DEFAULT uuid_stego_generate(),
    data jsonb,
    created_at timestamp DEFAULT now()
);

-- Create functional index using hidden timestamp
CREATE INDEX events_stego_time_idx ON events 
USING btree (uuid_stego_extract_timestamp(id));

-- Query by time range efficiently (PostgreSQL will use the index!)
SELECT * FROM events 
WHERE uuid_stego_extract_timestamp(id) BETWEEN 
  extract(epoch from '2024-01-01'::timestamp) * 1000000 AND 
  extract(epoch from now()) * 1000000
ORDER BY uuid_stego_extract_timestamp(id);
```

## Functional Indexing

For optimal performance, create functional indexes on the hidden timestamp:

```sql
-- Basic functional index for time-based queries
CREATE INDEX idx_table_stego_time ON your_table 
USING btree (uuid_stego_extract_timestamp(uuid_column));

-- Partial index for recent records only
CREATE INDEX idx_table_recent_stego ON your_table 
USING btree (uuid_stego_extract_timestamp(uuid_column))
WHERE uuid_stego_extract_timestamp(uuid_column) > extract(epoch from now() - interval '1 year') * 1000000;

-- Composite index with other columns
CREATE INDEX idx_table_user_time ON your_table 
USING btree (user_id, uuid_stego_extract_timestamp(uuid_column));
```

### Query Examples That Use The Index

```sql
-- Time range queries (FAST with functional index)
SELECT * FROM events 
WHERE uuid_stego_extract_timestamp(id) BETWEEN 1704067200000000 AND 1735689600000000;

-- Recent records (FAST)
SELECT * FROM events 
WHERE uuid_stego_extract_timestamp(id) > extract(epoch from now() - interval '24 hours') * 1000000
ORDER BY uuid_stego_extract_timestamp(id) DESC;

-- Pagination by time (FAST)
SELECT * FROM events 
WHERE uuid_stego_extract_timestamp(id) > 1704067200000000
ORDER BY uuid_stego_extract_timestamp(id)
LIMIT 100;
```

### Performance Notes

- ✅ **IMMUTABLE function**: `uuid_stego_extract_timestamp` is marked IMMUTABLE for index optimization
- ✅ **B-tree compatible**: Supports range queries, sorting, and inequality operators  
- ⚠️ **Index size**: Functional indexes require additional storage
- ⚠️ **Update overhead**: Index rebuilds on every UUID column update

## Functions

- `uuid_stego_generate()` - Generate new steganographic UUID
- `uuid_stego_extract_timestamp(uuid)` - Extract hidden timestamp 
- `uuid_stego_compare(uuid, uuid)` - Compare UUIDs by hidden timestamp
- `uuid_stego_set_seed(text)` - Set encryption seed
- `uuid_stego_get_seed()` - Get current seed
- `uuid_stego_set_encryption_mode(text)` - Set encryption algorithm (XOR/AES128/AES256)
- `uuid_stego_get_encryption_mode()` - Get current encryption mode
- Comparison operators: `<`, `<=`, `>`, `>=` (based on hidden timestamp)

## Encryption Modes

The extension provides multiple algorithms for timestamp obfuscation:

### Available Algorithms

- **XOR** (default): XOR-based obfuscation with SHA-256 key derivation from seed
- **AES128**: AES-128 encryption in ECB mode for cryptographically secure timestamp protection
- **AES256**: AES-256 encryption in ECB mode for enhanced security requirements

### Configuration

```sql
-- Check current encryption mode (default is XOR)
SELECT uuid_stego_get_encryption_mode();
-- Result: XOR

-- Switch to AES-128 for enhanced security
SELECT uuid_stego_set_encryption_mode('AES128');

-- Verify mode change
SELECT uuid_stego_get_encryption_mode();
-- Result: AES128

-- Generate UUIDs with AES-128 encryption
SELECT uuid_stego_generate();

-- Switch to maximum security AES-256
SELECT uuid_stego_set_encryption_mode('AES256');

-- Reset to default fast mode
SELECT uuid_stego_set_encryption_mode('XOR');
```

### Performance Comparison

| Mode | Security Level | Performance | Use Case |
|------|---------------|-------------|----------|
| **XOR** | Privacy protection | ~222,965 UUIDs/sec | Web applications, general use |
| **AES128** | Cryptographically secure | ~15,000 UUIDs/sec | Financial systems, compliance |
| **AES256** | Maximum security | ~11,000 UUIDs/sec | Government, highly sensitive data |

**Note**: Performance varies based on hardware. Systems with AES-NI instruction support will see significantly better AES performance.

### Mode Persistence

Encryption mode settings are per-session by default. To set system-wide defaults:

```sql
-- Set default mode in postgresql.conf or via ALTER SYSTEM
ALTER SYSTEM SET uuid_v8.encryption_mode = 'AES128';
SELECT pg_reload_conf();
```

### Compatibility Notes

- **Decryption compatibility**: UUIDs generated in one mode can only be decrypted in the same mode with the same seed
- **Migration**: When changing modes, existing UUIDs remain readable using the original mode setting
- **Mixed usage**: Different tables can use different encryption modes within the same database

## Security Considerations

### Seed Security
- **Keep your seed secret**: The seed is used to obfuscate timestamps
- **Rotate seeds periodically**: Consider seed rotation for enhanced security  
- **Unique seeds per environment**: Use different seeds for dev/staging/production
- **Strong seeds**: Use long, random seeds (minimum 16 characters recommended)

### Encryption Mode Selection
- **XOR mode**: Suitable for privacy protection where performance is critical
- **AES128 mode**: Use for compliance requirements (PCI DSS, HIPAA) and financial systems
- **AES256 mode**: Use for maximum security requirements (government, military, high-value targets)
- **Consider hardware**: AES-NI capable processors significantly improve AES performance

### Threat Model Assessment
- **XOR protection**: Prevents casual timestamp observation, suitable for internal systems
- **AES protection**: Prevents cryptographic attacks on timestamp values
- **Timing attacks**: Consider whether timestamp precision revelation matters for your use case

## Requirements

- PostgreSQL 12 or later
- PostgreSQL development headers
- OpenSSL library