-- Postgres init script — postgres-entrypoint-initdb.d 에서 실행됨 (volume 최초 init 시).
-- ADR 0002 T4: superuser 와 app role 을 분리한다. superuser 는 RLS 우회 가능하므로,
-- 앱은 NOSUPERUSER + NOBYPASSRLS 인 별도 role 로만 접속해야 한다.
--
-- 운영 환경에서는 비밀번호가 KMS/Vault 에서 주입되며 본 SQL 의 평문은 사용하지 않는다.
-- 본 스크립트는 dev 전용 — POSTGRES_USER (superuser, 마이그레이션·관리용) 와
-- genofinder_app (NOSUPERUSER, 앱 런타임용) 두 role 만 만든다.

CREATE ROLE genofinder_app LOGIN PASSWORD 'devpassword'
  NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB;

GRANT CONNECT ON DATABASE genofinder TO genofinder_app;
GRANT USAGE ON SCHEMA public TO genofinder_app;

-- 마이그레이션이 새 테이블을 만들 때 자동으로 권한 부여
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO genofinder_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO genofinder_app;

-- 이미 만들어진 테이블에도 적용 (idempotent)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO genofinder_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO genofinder_app;
