-- StayQR REV8 staging acceptance: Meta WhatsApp webhook atomic persistence
-- Run after Migration 114 on STAGING only.

with defs as (
  select pg_get_functiondef(
    'public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)'::regprocedure
  ) as body
), checks as (
  select '01_RPC_EXISTS' as check_name,
    to_regprocedure('public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)') is not null as ok

  union all
  select '02_SERVICE_ROLE_EXECUTE_ONLY',
    has_function_privilege('service_role','public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)','EXECUTE')
    and not has_function_privilege('authenticated','public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)','EXECUTE')
    and not has_function_privilege('anon','public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)','EXECUTE')

  union all
  select '03_RECIPIENT_ROW_LOCKED', body ilike '%for update%' from defs

  union all
  select '04_FAILED_CANNOT_DOWNGRADE_SUCCESS',
    body ilike '%successful_state_prevents_failed_downgrade%'
    and body ilike '%sent%delivered%read%' from defs

  union all
  select '05_FAILED_PROVIDER_ID_TERMINAL',
    body ilike '%failed_provider_message_is_terminal%' from defs

  union all
  select '06_LOWER_RANK_STATUS_IGNORED',
    body ilike '%lower_rank_status_ignored%' from defs

  union all
  select '07_EVENT_AND_RECIPIENT_IN_ONE_RPC',
    body ilike '%update public.guest_communication_recipients%'
    and body ilike '%insert into public.guest_communication_events%' from defs

  union all
  select '08_EVENT_IDEMPOTENT',
    body ilike '%on conflict (recipient_id, event_type) do nothing%' from defs

  union all
  select '09_UNKNOWN_PROVIDER_ID_SAFE',
    body ilike '%''matched'', false%' from defs

  union all
  select '10_SUPPORTED_STATUS_ALLOWLIST',
    body ilike '%sent%delivered%read%failed%' from defs

  union all
  select '11_SMALL_METADATA_BOUND',
    body ilike '%pg_column_size(v_metadata) > 4096%' from defs

  union all
  select '12_UNKNOWN_ID_RUNTIME_SAFE',
    coalesce((public.record_whatsapp_delivery_status(
      'stayqr-rev8-nonexistent-provider-message-id',
      'delivered',
      now(),
      null,
      null,
      '{"acceptance":true}'::jsonb
    )->>'matched')::boolean, true) is false
)
select check_name, case when ok then 'PASS' else 'FAIL' end as status
from checks
order by check_name;
