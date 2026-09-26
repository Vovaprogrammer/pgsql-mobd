-- =============================================================================
-- Создание базы данных marketplace.
-- Выполняется один раз, вне контекста самой базы (например, подключившись
-- к базе postgres). Отделено от schema.sql, так как CREATE DATABASE не может
-- выполняться в одном скрипте вместе с DDL внутри самой базы.
-- =============================================================================

CREATE DATABASE marketplace
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE marketplace
    IS 'Сквозной кейс — проектирование и разработка базы данных маркетплейса на PostgreSQL';
