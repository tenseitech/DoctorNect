-- RDS-like local: superuser rdsadmin only (no postgres role).
CREATE ROLE rds_superuser NOLOGIN;

CREATE ROLE doctornect_admin LOGIN CREATEROLE CREATEDB PASSWORD 'test';
GRANT rds_superuser TO doctornect_admin WITH INHERIT TRUE, SET TRUE;

CREATE DATABASE doctornect OWNER doctornect_admin;