/*
 * pg_uuid_v8.c
 * PostgreSQL UUID v8: Steganographic UUIDs with hidden timestamps
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/uuid.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/timestamp.h"
#include "miscadmin.h"
#include "catalog/pg_type.h"
#include <sys/time.h>
#include <openssl/sha.h>

PG_MODULE_MAGIC;

/* GUC variables */
static char *stego_seed = NULL;
static char *encryption_mode = NULL;

/* Default values */
#define DEFAULT_SEED "uuid_v8_default_seed_2024"
#define DEFAULT_ENCRYPTION_MODE "XOR"

/* Encryption modes */
typedef enum {
    ENCRYPTION_XOR,
    ENCRYPTION_AES128,
    ENCRYPTION_AES256
} encryption_mode_t;

/* AES key storage */
#ifdef USE_OPENSSL
#include <openssl/aes.h>
static AES_KEY cached_aes_encrypt_key;
static AES_KEY cached_aes_decrypt_key;
static bool aes_keys_initialized = false;
#endif

void _PG_init(void);
void _PG_fini(void);

/* Function declarations */
PG_FUNCTION_INFO_V1(uuid_stego_generate);
PG_FUNCTION_INFO_V1(uuid_stego_extract_timestamp);
PG_FUNCTION_INFO_V1(uuid_stego_compare);
PG_FUNCTION_INFO_V1(uuid_stego_set_seed);
PG_FUNCTION_INFO_V1(uuid_stego_get_seed);
PG_FUNCTION_INFO_V1(uuid_stego_lt);
PG_FUNCTION_INFO_V1(uuid_stego_le);
PG_FUNCTION_INFO_V1(uuid_stego_gt);
PG_FUNCTION_INFO_V1(uuid_stego_ge);

/*
 * Module initialization
 */
static bool
check_encryption_mode(char **newval, void **extra, GucSource source)
{
    if (*newval == NULL)
        return false;

    if (strcmp(*newval, "XOR") == 0 ||
        strcmp(*newval, "AES128") == 0 ||
        strcmp(*newval, "AES256") == 0)
        return true;

    GUC_check_errdetail("Valid encryption modes are: XOR, AES128, AES256");
    return false;
}

static void
assign_encryption_mode(const char *newval, void *extra)
{
    /* Invalidate cached AES keys when mode changes */
#ifdef USE_OPENSSL
    aes_keys_initialized = false;
#endif
}

void
_PG_init(void)
{
    DefineCustomStringVariable("uuid_v8.stego_seed",
                             "Seed for UUID v8 steganographic encoding",
                             "Controls the encryption key used for timestamp obfuscation",
                             &stego_seed,
                             DEFAULT_SEED,
                             PGC_USERSET,
                             0,
                             NULL,
                             NULL,
                             NULL);

    DefineCustomStringVariable("uuid_v8.encryption_mode",
                             "Encryption algorithm for UUID v8 timestamp obfuscation",
                             "Valid modes: XOR (fast), AES128 (secure), AES256 (maximum security)",
                             &encryption_mode,
                             DEFAULT_ENCRYPTION_MODE,
                             PGC_USERSET,
                             0,
                             check_encryption_mode,
                             assign_encryption_mode,
                             NULL);
}

void
_PG_fini(void)
{
    /* Cleanup if needed */
}

/*
 * Generate a 64-bit key from the seed using SHA-256
 */
static uint64
generate_key_from_seed(const char *seed)
{
    unsigned char hash[SHA256_DIGEST_LENGTH];
    uint64 key = 0;
    int i;

    if (!seed)
        seed = DEFAULT_SEED;

    SHA256((const unsigned char*)seed, strlen(seed), hash);

    /* Use first 8 bytes of hash as key */
    for (i = 0; i < 8; i++) {
        key = (key << 8) | hash[i];
    }

    return key;
}

/*
 * Get current timestamp in microseconds since Unix epoch
 */
static uint64
get_current_timestamp_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((uint64)tv.tv_sec * 1000000ULL) + tv.tv_usec;
}

/*
 * Get current encryption mode
 */
static encryption_mode_t
get_encryption_mode(void)
{
    if (!encryption_mode)
        return ENCRYPTION_XOR;

    if (strcmp(encryption_mode, "AES128") == 0)
        return ENCRYPTION_AES128;
    else if (strcmp(encryption_mode, "AES256") == 0)
        return ENCRYPTION_AES256;
    else
        return ENCRYPTION_XOR;
}

#ifdef USE_OPENSSL
/*
 * Initialize AES keys if needed
 */
static void
init_aes_keys(const char *seed)
{
    unsigned char hash[SHA256_DIGEST_LENGTH];
    encryption_mode_t mode = get_encryption_mode();
    int key_bits;

    if (aes_keys_initialized)
        return;

    if (mode != ENCRYPTION_AES128 && mode != ENCRYPTION_AES256)
        return;

    if (!seed)
        seed = DEFAULT_SEED;

    /* Generate key from seed */
    SHA256((const unsigned char*)seed, strlen(seed), hash);

    key_bits = (mode == ENCRYPTION_AES128) ? 128 : 256;

    /* Initialize AES keys */
    AES_set_encrypt_key(hash, key_bits, &cached_aes_encrypt_key);
    AES_set_decrypt_key(hash, key_bits, &cached_aes_decrypt_key);

    aes_keys_initialized = true;
}

/*
 * AES encrypt 64-bit timestamp
 */
static uint64
aes_encrypt_timestamp(uint64 timestamp)
{
    unsigned char plaintext[16] = {0};
    unsigned char ciphertext[16];
    uint64 result;

    init_aes_keys(stego_seed);

    /* Pack timestamp into 16-byte block (little-endian) */
    memcpy(plaintext, &timestamp, sizeof(uint64));

    /* Encrypt */
    AES_encrypt(plaintext, ciphertext, &cached_aes_encrypt_key);

    /* Extract first 8 bytes as result */
    memcpy(&result, ciphertext, sizeof(uint64));

    return result & 0xFFFFFFFFFFFFULL; /* 48-bit mask */
}

/*
 * AES decrypt 64-bit timestamp
 */
static uint64
aes_decrypt_timestamp(uint64 encrypted)
{
    unsigned char ciphertext[16] = {0};
    unsigned char plaintext[16];
    uint64 result;

    init_aes_keys(stego_seed);

    /* Pack encrypted data into 16-byte block */
    memcpy(ciphertext, &encrypted, sizeof(uint64));

    /* Decrypt */
    AES_decrypt(ciphertext, plaintext, &cached_aes_decrypt_key);

    /* Extract timestamp */
    memcpy(&result, plaintext, sizeof(uint64));

    return result;
}
#endif

/*
 * Encrypt timestamp using current algorithm
 */
static uint64
encrypt_timestamp(uint64 timestamp, uint64 xor_key)
{
    encryption_mode_t mode = get_encryption_mode();

    switch (mode) {
#ifdef USE_OPENSSL
        case ENCRYPTION_AES128:
        case ENCRYPTION_AES256:
            return aes_encrypt_timestamp(timestamp);
#endif
        case ENCRYPTION_XOR:
        default:
            /* XOR encryption - timestamp is 48 bits, so mask it */
            return (timestamp ^ xor_key) & 0xFFFFFFFFFFFFULL;
    }
}

/*
 * Decrypt timestamp using current algorithm
 */
static uint64
decrypt_timestamp(uint64 encrypted, uint64 xor_key)
{
    encryption_mode_t mode = get_encryption_mode();

    switch (mode) {
#ifdef USE_OPENSSL
        case ENCRYPTION_AES128:
        case ENCRYPTION_AES256:
            return aes_decrypt_timestamp(encrypted);
#endif
        case ENCRYPTION_XOR:
        default:
            /* XOR decryption (same as encryption) */
            return (encrypted ^ xor_key) & 0xFFFFFFFFFFFFULL;
    }
}

/*
 * Generate steganographic UUID
 */
Datum
uuid_stego_generate(PG_FUNCTION_ARGS)
{
    pg_uuid_t *uuid;
    uint64 timestamp;
    uint64 encrypted_timestamp;
    uint64 key;
    uint32 random_data[2];
    int i;

    uuid = (pg_uuid_t *) palloc(sizeof(pg_uuid_t));

    /* Get current timestamp and encrypt it */
    timestamp = get_current_timestamp_us();
    key = generate_key_from_seed(stego_seed);
    encrypted_timestamp = encrypt_timestamp(timestamp, key);

    /* Store encrypted timestamp in first 6 bytes */
    for (i = 0; i < 6; i++) {
        uuid->data[i] = (encrypted_timestamp >> (40 - i * 8)) & 0xFF;
    }

    /* Generate random data for remaining bytes */
    for (i = 0; i < 2; i++) {
        random_data[i] = random();
    }

    /* Fill bytes 6-13 with random data */
    for (i = 6; i < 14; i++) {
        uuid->data[i] = (random_data[(i-6)/4] >> ((3 - ((i-6) % 4)) * 8)) & 0xFF;
    }

    /* Set version to 4 (random UUID) - bits 48-51 */
    uuid->data[6] = (uuid->data[6] & 0x0F) | 0x40;

    /* Set variant bits - bits 64-65 */
    uuid->data[8] = (uuid->data[8] & 0x3F) | 0x80;

    /* Fill remaining bytes with random data */
    for (i = 14; i < 16; i++) {
        uuid->data[i] = random() & 0xFF;
    }

    PG_RETURN_UUID_P(uuid);
}

/*
 * Extract hidden timestamp from steganographic UUID
 */
Datum
uuid_stego_extract_timestamp(PG_FUNCTION_ARGS)
{
    pg_uuid_t *uuid = PG_GETARG_UUID_P(0);
    uint64 encrypted_timestamp = 0;
    uint64 timestamp;
    uint64 key;
    int i;

    /* Extract encrypted timestamp from first 6 bytes */
    for (i = 0; i < 6; i++) {
        encrypted_timestamp = (encrypted_timestamp << 8) | uuid->data[i];
    }

    /* Decrypt timestamp */
    key = generate_key_from_seed(stego_seed);
    timestamp = decrypt_timestamp(encrypted_timestamp, key);

    PG_RETURN_INT64((int64)timestamp);
}

/*
 * Compare two steganographic UUIDs by their hidden timestamps
 */
Datum
uuid_stego_compare(PG_FUNCTION_ARGS)
{
    pg_uuid_t *uuid1 = PG_GETARG_UUID_P(0);
    pg_uuid_t *uuid2 = PG_GETARG_UUID_P(1);
    uint64 ts1, ts2;
    uint64 key;
    uint64 encrypted_ts1 = 0, encrypted_ts2 = 0;
    int i;

    key = generate_key_from_seed(stego_seed);

    /* Extract and decrypt timestamps */
    for (i = 0; i < 6; i++) {
        encrypted_ts1 = (encrypted_ts1 << 8) | uuid1->data[i];
        encrypted_ts2 = (encrypted_ts2 << 8) | uuid2->data[i];
    }

    ts1 = decrypt_timestamp(encrypted_ts1, key);
    ts2 = decrypt_timestamp(encrypted_ts2, key);

    if (ts1 < ts2)
        PG_RETURN_INT32(-1);
    else if (ts1 > ts2)
        PG_RETURN_INT32(1);
    else
        PG_RETURN_INT32(0);
}

/*
 * Set steganographic seed
 */
Datum
uuid_stego_set_seed(PG_FUNCTION_ARGS)
{
    text *seed_text = PG_GETARG_TEXT_P(0);
    char *new_seed;

    new_seed = text_to_cstring(seed_text);

    /* Update GUC variable */
    SetConfigOption("uuid_v8.stego_seed", new_seed, PGC_USERSET, PGC_S_SESSION);

    PG_RETURN_VOID();
}

/*
 * Get current steganographic seed
 */
Datum
uuid_stego_get_seed(PG_FUNCTION_ARGS)
{
    const char *current_seed = stego_seed ? stego_seed : DEFAULT_SEED;
    PG_RETURN_TEXT_P(cstring_to_text(current_seed));
}

/* Comparison operators for steganographic UUIDs */

Datum
uuid_stego_lt(PG_FUNCTION_ARGS)
{
    Datum result = DirectFunctionCall2(uuid_stego_compare,
                                     PG_GETARG_DATUM(0),
                                     PG_GETARG_DATUM(1));
    PG_RETURN_BOOL(DatumGetInt32(result) < 0);
}

Datum
uuid_stego_le(PG_FUNCTION_ARGS)
{
    Datum result = DirectFunctionCall2(uuid_stego_compare,
                                     PG_GETARG_DATUM(0),
                                     PG_GETARG_DATUM(1));
    PG_RETURN_BOOL(DatumGetInt32(result) <= 0);
}

Datum
uuid_stego_gt(PG_FUNCTION_ARGS)
{
    Datum result = DirectFunctionCall2(uuid_stego_compare,
                                     PG_GETARG_DATUM(0),
                                     PG_GETARG_DATUM(1));
    PG_RETURN_BOOL(DatumGetInt32(result) > 0);
}

Datum
uuid_stego_ge(PG_FUNCTION_ARGS)
{
    Datum result = DirectFunctionCall2(uuid_stego_compare,
                                     PG_GETARG_DATUM(0),
                                     PG_GETARG_DATUM(1));
    PG_RETURN_BOOL(DatumGetInt32(result) >= 0);
}