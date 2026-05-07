\set ON_ERROR_STOP on

/*
 * User creation
 */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '__DBUSER__') THEN
    CREATE USER '__DBUSER__' WITH
      LOGIN
      NOSUPERUSER
      INHERIT
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION
      PASSWORD '__DBPASS__';
  END IF;
END $$;

/*
 * Database creation
 */
create database '__DBNAME__' owner '__DBUSER__';
\c "dbname='__DBNAME__'"
 create extension if not exists postgis schema public;
 create extension if not exists pgcrypto schema public;
 create extension if not exists pg_trgm schema pg_catalog;

/**
 * create structure
 */
BEGIN;
\c "dbname='__DBNAME__' user='__DBUSER__' password='__DBPASS__' host=localhost"
\ir /var/www/collec2App/collec-science/install/pgsql/collec_create.sql
COMMIT;
