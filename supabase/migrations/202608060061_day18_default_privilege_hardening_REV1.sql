-- ============================================================================
-- StayQR v1.0 — Day 18 Default-Privilege Hardening REV1
-- Version: 202608060061
-- Purpose: preserve explicit grant/RLS control for every future public object.
-- ============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

SELECT pg_advisory_xact_lock(
  hashtext('stayqr:202608060061:default-privilege-hardening-rev1')
);

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

DO $stayqr_day18_default_acl_check$
DECLARE
  v_unsafe_default_acl_count bigint;
BEGIN
  SELECT count(*)
  INTO v_unsafe_default_acl_count
  FROM pg_catalog.pg_default_acl d
  JOIN pg_catalog.pg_namespace n
    ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) x
  JOIN pg_catalog.pg_roles grantee_role
    ON grantee_role.oid = x.grantee
  JOIN pg_catalog.pg_roles owner_role
    ON owner_role.oid = d.defaclrole
  WHERE n.nspname = 'public'
    AND owner_role.rolname = 'postgres'
    AND grantee_role.rolname IN ('anon', 'authenticated');

  IF v_unsafe_default_acl_count <> 0 THEN
    RAISE EXCEPTION
      'Day 18 default-privilege hardening failed: % anon/authenticated default ACL entries remain.',
      v_unsafe_default_acl_count;
  END IF;
END
$stayqr_day18_default_acl_check$;

COMMIT;
