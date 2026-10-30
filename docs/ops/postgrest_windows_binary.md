# Pinned PostgREST Windows Binary Specification

This document records the official pinned PostgREST binary for local development, staging verification, and RDS scratch replay on Windows environments.

## Binary Details
- **Version**: PostgREST v12.2.3 (`519615d`)
- **Release Source**: https://github.com/PostgREST/postgrest/releases/download/v12.2.3/postgrest-v12.2.3-windows-x64.zip
- **Archive Path**: `.bin/postgrest-v12.2.3-windows-x64.zip`
- **Archive SHA256**: `a850cd1cf5b208972f4db2803656c645436ad333882480685e052d45706c1966`
- **Executable Path**: `.bin/postgrest.exe`
- **Executable SHA256**: `01ee186e6e9904a1fb8183a51b5b6d2b6695720c29f65325f6fc678708360bb8`

## Runtime Prerequisites
- **PostgreSQL Client Libraries**: The binary dynamically links to `libpq.dll` (from PostgreSQL 17 at `C:\Program Files\PostgreSQL\17\bin`). The directory must be in `PATH` when executing `postgrest.exe`.

