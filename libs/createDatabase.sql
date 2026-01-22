/*
 * Database creation
 */
create database dbcollec owner collec;
\c "dbname=dbcollec"
 create extension if not exists postgis schema public;
 create extension if not exists pgcrypto schema public;
 create extension if not exists pg_trgm schema pg_catalog;


\c "dbname=dbcollec user=collec password=xxxxx host=localhost"

/**
 * create structure
 */
\ir /var/www/collec2App/collec-science/install/pgsql/collec_create.sql
