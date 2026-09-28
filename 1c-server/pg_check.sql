\echo ==VERSION==
SELECT version();
\echo ==DBS==
SELECT datname, pg_encoding_to_char(encoding) AS enc, datcollate, datctype FROM pg_database ORDER BY datname;
\echo ==ROLES==
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin FROM pg_roles ORDER BY rolname;
