-- StayQR Day 1 schema snapshot
-- Run this in Supabase Dashboard > SQL Editor on the CURRENT project.
-- Copy/download the single JSON result and keep it with the project audit.
-- This query is read-only and does not change the database.

select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'tables', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.table_name), '[]'::jsonb)
      from (
        select table_name
        from information_schema.tables
        where table_schema = 'public'
          and table_type = 'BASE TABLE'
      ) t
    ),
    'columns', (
      select coalesce(jsonb_agg(to_jsonb(c) order by c.table_name, c.ordinal_position), '[]'::jsonb)
      from (
        select
          table_name,
          ordinal_position,
          column_name,
          data_type,
          udt_name,
          is_nullable,
          column_default
        from information_schema.columns
        where table_schema = 'public'
      ) c
    ),
    'constraints', (
      select coalesce(jsonb_agg(to_jsonb(k) order by k.table_name, k.constraint_name), '[]'::jsonb)
      from (
        select
          tc.table_name,
          tc.constraint_name,
          tc.constraint_type,
          kcu.column_name,
          ccu.table_name as referenced_table,
          ccu.column_name as referenced_column
        from information_schema.table_constraints tc
        left join information_schema.key_column_usage kcu
          on tc.constraint_name = kcu.constraint_name
         and tc.constraint_schema = kcu.constraint_schema
        left join information_schema.constraint_column_usage ccu
          on tc.constraint_name = ccu.constraint_name
         and tc.constraint_schema = ccu.constraint_schema
        where tc.table_schema = 'public'
      ) k
    ),
    'indexes', (
      select coalesce(jsonb_agg(to_jsonb(i) order by i.tablename, i.indexname), '[]'::jsonb)
      from (
        select tablename, indexname, indexdef
        from pg_indexes
        where schemaname = 'public'
      ) i
    ),
    'rls', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.tablename), '[]'::jsonb)
      from (
        select
          c.relname as tablename,
          c.relrowsecurity as rls_enabled,
          c.relforcerowsecurity as rls_forced
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind = 'r'
      ) r
    ),
    'policies', (
      select coalesce(jsonb_agg(to_jsonb(p) order by p.tablename, p.policyname), '[]'::jsonb)
      from (
        select
          tablename,
          policyname,
          permissive,
          roles,
          cmd,
          qual,
          with_check
        from pg_policies
        where schemaname = 'public'
      ) p
    ),
    'functions', (
      select coalesce(jsonb_agg(to_jsonb(f) order by f.function_name), '[]'::jsonb)
      from (
        select
          p.proname as function_name,
          pg_get_function_identity_arguments(p.oid) as arguments,
          pg_get_function_result(p.oid) as result,
          p.prosecdef as security_definer
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
      ) f
    ),
    'triggers', (
      select coalesce(jsonb_agg(to_jsonb(g) order by g.event_object_table, g.trigger_name), '[]'::jsonb)
      from (
        select
          event_object_table,
          trigger_name,
          event_manipulation,
          action_timing,
          action_statement
        from information_schema.triggers
        where trigger_schema = 'public'
      ) g
    )
  )
) as stayqr_schema_snapshot;
