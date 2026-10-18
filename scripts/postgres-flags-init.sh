#!/bin/bash
# Roda no primeiro start do container postgres-flags.
# O enunciado pede exatamente 2 instancias PostgreSQL, entao esta instancia
# hospeda dois bancos: flags_db (criado via POSTGRES_DB) e targeting_db.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE targeting_db;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname targeting_db -f /schemas/targeting.sql

echo "targeting_db criado e schema aplicado."
