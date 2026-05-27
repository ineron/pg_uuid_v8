# pg_uuid_v8

**PostgreSQL UUID v8 Extension** - Steganographic UUIDs with hidden timestamps.

## Overview

`pg_uuid_v8` is a PostgreSQL extension that implements **UUID v8** - a novel UUID standard that solves the classic dilemma between UUID v4 (random, slow indexing) and UUID v7 (timestamp-based, fast indexing but reveals creation time). This PostgreSQL-specific implementation provides steganographic functionality where UUIDs appear as standard v4 UUIDs but contain hidden timestamps for efficient indexing and sorting.

### Key Features

- **Steganographic UUIDs**: Look like random UUID v4 but contain hidden timestamps
- **Efficient Indexing**: Sort and index by hidden timestamp without revealing creation time
- **Unpredictable**: External users cannot determine creation time from UUID appearance
- **Seed-based Obfuscation**: Uses configurable seeds for timestamp encryption
- **Full PostgreSQL Integration**: Custom operators and comparison functions

## The Problem Solved

UUID evolution forced developers to choose between performance and privacy:
- **UUID v4**: Truly random and private, but poor indexing performance
- **UUID v7**: Great indexing performance, but reveals creation timestamp
- **UUID v8**: Best of both worlds - efficient indexing with timestamp privacy

UUID v8 bridges this gap by providing UUIDs that are:
- **Externally identical** to UUID v4 (maintains unpredictability)
- **Internally optimized** like UUID v7 (enables efficient indexing)
- **Cryptographically protected** (configurable XOR/AES encryption modes)

## Building and Installation

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

pg_uuid_v8 supports multiple encryption algorithms for timestamp obfuscation, offering different security/performance trade-offs:

### Available Modes

- **XOR** (default): Fast XOR-based encryption with SHA-256 key derivation
- **AES128**: AES-128 encryption for cryptographically secure obfuscation 
- **AES256**: AES-256 encryption for maximum security

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