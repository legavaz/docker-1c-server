-- Ручной вариант подготовки БД PostgreSQL для 1С.
-- ВНИМАНИЕ: предпочтительный способ — дать 1С создать БД самой
-- (rac infobase create ... --create-database): она поставит и расширения, и схему.
-- Этот скрипт — альтернатива, если БД создаётся заранее вручную.
-- Выполнять суперпользователем: psql -U postgres -h <PG_HOST> -f pg_setup.sql

CREATE ROLE usr1cv8 LOGIN PASSWORD 'usr1cv8';
CREATE DATABASE base1c OWNER usr1cv8 ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;

\connect base1c

-- Обязательные расширения 1С:Предприятие (входят в 1C-сборку PostgreSQL).
CREATE EXTENSION IF NOT EXISTS mchar;
CREATE EXTENSION IF NOT EXISTS fasttrun;
CREATE EXTENSION IF NOT EXISTS fulleq;
