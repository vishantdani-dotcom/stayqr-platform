begin;

-- StayQR Commercial-Ready REV8
-- Meta WhatsApp webhook delivery-state hardening.
-- The Edge Function verifies Meta HMAC first, then delegates each matched status
-- to this service-role-only transactional RPC so recipient status + event evidence
-- either persist together or fail together.

create or replace function public.record_whatsapp_delivery_status(
  p_provider_message_id text,
  p_status text,
  p_status_at timestamptz,
  p_error_code text default null,
  p_error_message text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider_message_id text := btrim(coalesce(p_provider_message_id, ''));
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_status_at timestamptz := coalesce(p_status_at, now());
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_recipient public.guest_communication_recipients%rowtype;
  v_current text;
  v_current_rank integer;
  v_incoming_rank integer;
  v_applied boolean := false;
  v_idempotent boolean := false;
  v_ignored_reason text;
begin
  if v_provider_message_id = '' or char_length(v_provider_message_id) > 255 then
    raise exception 'A valid provider message id is required.';
  end if;

  if v_status not in ('sent', 'delivered', 'read', 'failed') then
    raise exception 'Unsupported WhatsApp delivery status.';
  end if;

  if jsonb_typeof(v_metadata) <> 'object' or pg_column_size(v_metadata) > 4096 then
    raise exception 'WhatsApp delivery metadata must be a small JSON object.';
  end if;

  select recipient.*
  into v_recipient
  from public.guest_communication_recipients recipient
  where recipient.provider_message_id = v_provider_message_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'matched', false,
      'applied', false,
      'idempotent', false,
      'provider_message_id', v_provider_message_id
    );
  end if;

  v_current := lower(coalesce(v_recipient.status, ''));
  v_current_rank := case v_current
    when 'sent' then 1
    when 'delivered' then 2
    when 'read' then 3
    else 0
  end;
  v_incoming_rank := case v_status
    when 'sent' then 1
    when 'delivered' then 2
    when 'read' then 3
    else -1
  end;

  -- A provider failure must never downgrade a message that has already reached
  -- a successful delivery state. A failure for the same provider message id is
  -- otherwise terminal; retries use a new provider message id.
  if v_status = 'failed' then
    if v_current in ('sent', 'delivered', 'read') then
      v_ignored_reason := 'successful_state_prevents_failed_downgrade';
    elsif v_current = 'failed' then
      v_idempotent := true;
    else
      update public.guest_communication_recipients
      set
        status = 'failed',
        failed_at = coalesce(failed_at, v_status_at),
        error_code = left(coalesce(nullif(btrim(p_error_code), ''), 'provider_failed'), 80),
        error_message = left(coalesce(nullif(btrim(p_error_message), ''), 'Meta reported message failure.'), 500)
      where id = v_recipient.id;
      v_applied := true;
    end if;
  else
    if v_current = 'failed' then
      v_ignored_reason := 'failed_provider_message_is_terminal';
    elsif v_incoming_rank < v_current_rank then
      v_ignored_reason := 'lower_rank_status_ignored';
    elsif v_incoming_rank = v_current_rank and v_current = v_status then
      v_idempotent := true;
    else
      update public.guest_communication_recipients
      set
        status = v_status,
        sent_at = case
          when v_status = 'sent' then coalesce(sent_at, v_status_at)
          else sent_at
        end,
        delivered_at = case
          when v_status = 'delivered' then coalesce(delivered_at, v_status_at)
          else delivered_at
        end,
        read_at = case
          when v_status = 'read' then coalesce(read_at, v_status_at)
          else read_at
        end,
        error_code = case when v_status in ('sent', 'delivered', 'read') then null else error_code end,
        error_message = case when v_status in ('sent', 'delivered', 'read') then null else error_message end
      where id = v_recipient.id;
      v_applied := true;
    end if;
  end if;

  -- Persist event evidence only for a state that is current/applied or an exact
  -- duplicate of that same state. Ignored stale/downgrade statuses are not
  -- recorded as authoritative delivery events.
  if v_applied or v_idempotent then
    insert into public.guest_communication_events(
      hotel_id,
      guest_id,
      campaign_id,
      recipient_id,
      channel,
      event_type,
      provider_message_id,
      metadata,
      created_at
    ) values (
      v_recipient.hotel_id,
      v_recipient.guest_id,
      v_recipient.campaign_id,
      v_recipient.id,
      'whatsapp',
      v_status,
      v_provider_message_id,
      v_metadata || case when v_status = 'failed' then jsonb_build_object('provider_failure', true) else '{}'::jsonb end,
      v_status_at
    )
    on conflict (recipient_id, event_type) do nothing;
  end if;

  return jsonb_build_object(
    'ok', true,
    'matched', true,
    'applied', v_applied,
    'idempotent', v_idempotent,
    'ignored_reason', v_ignored_reason,
    'recipient_id', v_recipient.id,
    'hotel_id', v_recipient.hotel_id,
    'provider_message_id', v_provider_message_id,
    'incoming_status', v_status,
    'current_status', case when v_applied then v_status else v_current end
  );
end;
$$;

revoke all on function public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb)
  to service_role;

comment on function public.record_whatsapp_delivery_status(text,text,timestamptz,text,text,jsonb) is
  'StayQR REV8 service-role-only atomic Meta WhatsApp delivery-state persistence. Enforces monotonic status transitions and writes recipient state plus event evidence in one database transaction.';

commit;
