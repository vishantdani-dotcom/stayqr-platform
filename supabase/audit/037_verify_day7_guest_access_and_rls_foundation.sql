-- ============================================================================
-- StayQR v1.0
-- Audit 037: Verify Day 7 guest access and RLS foundation
-- Expected: 22 rows and every passed value = true.
-- ============================================================================

with tests(test_name, passed, details) as (
  values
    (
      'guest_access_token_table',
      to_regclass('public.guest_access_tokens') is not null,
      'Signed guest access token metadata table exists.'
    ),
    (
      'private_signing_key_table',
      to_regclass('private.guest_access_signing_keys') is not null,
      'Guest token signing keys are stored only in the private schema.'
    ),
    (
      'active_signing_key',
      (select count(*) = 1 from private.guest_access_signing_keys where status = 'active'),
      'Exactly one guest access signing key is active.'
    ),
    (
      'guest_token_rls',
      coalesce((
        select c.relrowsecurity
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'guest_access_tokens'
      ), false),
      'Guest token metadata is protected by RLS.'
    ),
    (
      'no_raw_token_secret_column',
      not exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'guest_access_tokens'
          and column_name in ('token', 'access_token', 'secret', 'signing_secret')
      ),
      'The public token table stores no raw access token or signing secret.'
    ),
    (
      'guest_session_token_trigger',
      exists (
        select 1
        from pg_trigger
        where tgrelid = 'public.guest_sessions'::regclass
          and tgname = 'guest_sessions_sync_guest_access'
          and not tgisinternal
      ),
      'Guest access follows authoritative guest-session lifecycle changes.'
    ),
    (
      'active_stays_have_tokens',
      not exists (
        select 1
        from public.guest_sessions gs
        where gs.status = 'active'
          and coalesce(gs.extended_until, gs.checkout_time) > now()
          and not exists (
            select 1
            from public.guest_access_tokens t
            where t.guest_session_id = gs.id
              and t.hotel_id = gs.hotel_id
              and t.room_id = gs.room_id
              and t.status = 'active'
              and t.expires_at > now()
          )
      ),
      'Every current active stay has exactly scoped signed guest access.'
    ),
    (
      'token_tenant_consistency',
      not exists (
        select 1
        from public.guest_access_tokens t
        join public.guest_sessions gs on gs.id = t.guest_session_id
        where t.hotel_id <> gs.hotel_id
           or t.room_id <> gs.room_id
      ),
      'No guest token crosses hotel, room or stay ownership.'
    ),
    (
      'one_active_token_per_stay',
      not exists (
        select 1
        from public.guest_access_tokens
        where status = 'active'
        group by guest_session_id
        having count(*) > 1
      ),
      'A guest stay cannot have duplicate active access tokens.'
    ),
    (
      'food_order_items_hotel_scope',
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'food_order_items'
          and column_name = 'hotel_id'
          and is_nullable = 'NO'
      ),
      'Every food order line item carries a mandatory hotel scope.'
    ),
    (
      'food_order_items_tenant_consistency',
      not exists (
        select 1
        from public.food_order_items foi
        join public.food_orders fo on fo.id = foi.order_id
        join public.menu_items mi on mi.id = foi.menu_item_id
        where foi.hotel_id <> fo.hotel_id
           or foi.hotel_id <> mi.hotel_id
      )
      and exists (
        select 1
        from pg_trigger
        where tgrelid = 'public.food_order_items'::regclass
          and tgname = 'food_order_items_enforce_tenant'
          and not tgisinternal
      ),
      'Food order line items are enforced to the same hotel as both order and menu item.'
    ),
    (
      'approved_guest_rpcs_exist',
      to_regprocedure('public.resolve_guest_portal(text,text)') is not null
      and to_regprocedure('public.get_guest_service_requests(text,text)') is not null
      and to_regprocedure('public.create_guest_service_request(text,text,text)') is not null
      and to_regprocedure('public.get_guest_food_menu(text,text)') is not null
      and to_regprocedure('public.get_guest_food_orders(text,text)') is not null
      and to_regprocedure('public.place_guest_food_order(text,text,jsonb)') is not null,
      'All six narrow guest RPCs are installed.'
    ),
    (
      'guest_rpcs_security_definer',
      not exists (
        select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in (
            'resolve_guest_portal',
            'get_guest_service_requests',
            'create_guest_service_request',
            'get_guest_food_menu',
            'get_guest_food_orders',
            'place_guest_food_order'
          )
          and not p.prosecdef
      ),
      'Guest RPCs validate signed access inside security-definer boundaries.'
    ),
    (
      'anon_guest_rpc_grants',
      has_function_privilege('anon', 'public.resolve_guest_portal(text,text)', 'EXECUTE')
      and has_function_privilege('anon', 'public.get_guest_service_requests(text,text)', 'EXECUTE')
      and has_function_privilege('anon', 'public.create_guest_service_request(text,text,text)', 'EXECUTE')
      and has_function_privilege('anon', 'public.get_guest_food_menu(text,text)', 'EXECUTE')
      and has_function_privilege('anon', 'public.get_guest_food_orders(text,text)', 'EXECUTE')
      and has_function_privilege('anon', 'public.place_guest_food_order(text,text,jsonb)', 'EXECUTE'),
      'Anonymous users can execute only token-validated guest capabilities.'
    ),
    (
      'no_anon_table_grants',
      not exists (
        select 1
        from information_schema.role_table_grants
        where table_schema = 'public'
          and grantee = 'anon'
      ),
      'Anonymous direct access to public tables is fully revoked.'
    ),
    (
      'no_anon_table_policies',
      not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and ('anon' = any(roles) or 'public' = any(roles))
      ),
      'No public-table RLS policy authorizes anon or PUBLIC.'
    ),
    (
      'all_tenant_tables_rls',
      not exists (
        select 1
        from information_schema.columns col
        join pg_class c on c.relname = col.table_name
        join pg_namespace n on n.oid = c.relnamespace
        where col.table_schema = 'public'
          and col.column_name = 'hotel_id'
          and n.nspname = 'public'
          and c.relkind in ('r', 'p')
          and not c.relrowsecurity
      ),
      'Every public table carrying hotel_id has RLS enabled.'
    ),
    (
      'legacy_compatibility_tables_authenticated_only',
      not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = any(array[
            'rooms', 'guests', 'guest_sessions', 'hotel_info', 'feedback',
            'menu_categories', 'menu_items', 'food_orders', 'food_order_items',
            'service_requests', 'notifications'
          ])
          and not ('authenticated' = any(roles))
      ),
      'Former guest-compatible tables now use authenticated-only RLS.'
    ),
    (
      'staff_link_admin_rpcs',
      to_regprocedure('public.get_guest_access_links(uuid)') is not null
      and to_regprocedure('public.rotate_guest_access_token(uuid,uuid,text)') is not null
      and to_regprocedure('public.revoke_guest_access_token(uuid,uuid,text)') is not null
      and has_function_privilege('authenticated', 'public.get_guest_access_links(uuid)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.get_guest_access_links(uuid)', 'EXECUTE'),
      'Guest link administration is authenticated and unavailable to anon.'
    ),
    (
      'private_storage_buckets',
      (select count(*) = 2
       from storage.buckets
       where id in ('hotel-assets', 'guest-documents')
         and public = false),
      'Hotel assets and guest documents use private Storage buckets.'
    ),
    (
      'storage_policy_count',
      (select count(*) = 8
       from pg_policies
       where schemaname = 'storage'
         and tablename = 'objects'
         and policyname in (
           'stayqr_hotel_assets_select',
           'stayqr_hotel_assets_insert',
           'stayqr_hotel_assets_update',
           'stayqr_hotel_assets_delete',
           'stayqr_guest_documents_select',
           'stayqr_guest_documents_insert',
           'stayqr_guest_documents_update',
           'stayqr_guest_documents_delete'
         )),
      'Eight hotel-folder-scoped Storage policies are installed.'
    ),
    (
      'storage_buckets_not_anon',
      not exists (
        select 1
        from pg_policies
        where schemaname = 'storage'
          and tablename = 'objects'
          and policyname like 'stayqr_%'
          and ('anon' = any(roles) or 'public' = any(roles))
      ),
      'StayQR Storage policies never authorize anonymous access.'
    )
)
select test_name, passed, details
from tests
order by test_name;
