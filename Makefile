# PostgreSQL UUID v8 extension Makefile

EXTENSION = pg_uuid_v8
DATA = pg_uuid_v8--1.0.sql
REGRESS = pg_uuid_v8_test

MODULE_big = pg_uuid_v8
OBJS = pg_uuid_v8.o

# Add OpenSSL support for cryptographic functions
PG_CPPFLAGS = -I$(shell pkg-config --cflags-only-I openssl) -DUSE_OPENSSL
SHLIB_LINK = $(shell pkg-config --libs openssl)

# Disable LLVM bitcode generation to avoid llvm-lto errors
NO_LLVM = 1

# PostgreSQL build system
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)