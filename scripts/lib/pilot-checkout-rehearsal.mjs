import { readFileSync } from 'node:fs'
import { contracts, migrationSql, rollbackSql } from './pilot-checkout-compatibility.mjs'
const root = new URL('../../', import.meta.url)
const read = (path) => readFileSync(new URL(path,root),'utf8').replaceAll('\r','')
const inner = (sql) => sql.replace(/^begin;\n/m,'').replace(/^commit;\n/m,'')
const tables = ['discount_approvals','folio_adjustments','folio_collections','folio_items','folios','invoice_items','invoices']
const restrict = tables.map(t=>`revoke insert, update, delete on public.${t} from authenticated;`).join('\n')
const guard = `do $guard$ begin
  if not exists (select 1 from public.hotels where id='c6f16ea5-dcb0-40c3-a483-e628a5ea177c' and slug='20e-test-hotel')
    or not exists (select 1 from public.rooms where id='f7afde3e-ca57-473a-bf69-3e82b8755b72' and hotel_id='c6f16ea5-dcb0-40c3-a483-e628a5ea177c' and status='available') then
    raise exception 'Staging-only available fixture guard failed.';
  end if;
end; $guard$;`
function existingScenarios() {
  let sql = read('supabase/staging/202609030106_pilot_checkout_folio_TRANSACTIONAL_TEST.sql')
  sql = sql.slice(sql.indexOf("select set_config('request.jwt.claim.sub'"),sql.indexOf('do $security$'))
  const start = sql.indexOf('        rejected := false;\n        begin\n          perform public.checkout_guest_session')
  const end = sql.indexOf('\n      end if;\n      raise sqlstate',start)
  if(start<0||end<0) throw new Error('Unknown inherited test shape')
  sql = sql.slice(0,start)+`        checkout_result := public.checkout_guest_session(hotel_id_value, session_id_value,
          scenario.tax_rate, scenario.discount_type, scenario.discount_value, false, 'cash', null, 'duplicate', false);
        if checkout_result ->> 'already_checked_out' <> 'true'
          or checkout_result ->> 'invoice_id' <> invoice_row.id::text
          or (checkout_result ->> 'amount_collected_at_checkout')::numeric <> 0
          or before_count <> (select count(*) from public.folio_adjustments where hotel_id=hotel_id_value and folio_id=folio_row.id)
          or (select count(*) from public.reservation_checkout_events where hotel_id=hotel_id_value and guest_session_id=session_id_value)<>1 then
          raise exception 'Duplicate checkout changed invoice/discount/checkout evidence.';
        end if;`+sql.slice(end)
  return sql+'\nreset role;\n'
}
const securityTests = `
reset role;
do $security$
declare table_name text; function_name text; rejected boolean;
begin
  foreach table_name in array array[${tables.map(t=>`'${t}'`).join(',')}] loop
    if has_table_privilege('authenticated','public.'||table_name,'INSERT')
      or has_table_privilege('authenticated','public.'||table_name,'UPDATE')
      or has_table_privilege('authenticated','public.'||table_name,'DELETE') then
      raise exception 'Production-equivalent finance permissions were not enforced: %',table_name;
    end if;
  end loop;
  foreach function_name in array array['public.checkout_guest_session','public.checkout_guest_session_day20_legacy'] loop
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub','fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae',true);
    perform set_config('request.jwt.claims','{"sub":"fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae","role":"authenticated"}',true);
    rejected := false;
    begin
      execute format('select %s($1,$2,0,''fixed'',0,false,''cash'',null,null,false)',function_name)
        using '00000000-0000-0000-0000-000000000107'::uuid,'e50ee898-1edd-44f2-b2de-bbbc78de8a95'::uuid;
    exception when others then
      if sqlerrm <> 'Reservation write access denied.' then raise; end if;
      rejected := true;
    end;
    if not rejected then raise exception 'Cross-hotel checkout allowed: %',function_name; end if;
    perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000107',true);
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000107","role":"authenticated"}',true);
    rejected := false;
    begin
      execute format('select %s($1,$2,0,''fixed'',0,false,''cash'',null,null,false)',function_name)
        using 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c'::uuid,'e50ee898-1edd-44f2-b2de-bbbc78de8a95'::uuid;
    exception when others then
      if sqlerrm <> 'Reservation write access denied.' then raise; end if;
      rejected := true;
    end;
    if not rejected then raise exception 'Unauthorized actor checkout allowed: %',function_name; end if;
    execute 'reset role';
  end loop;
  if has_function_privilege('authenticated','private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)','EXECUTE')
    or has_function_privilege('anon','private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)','EXECUTE')
    or has_function_privilege('authenticated','private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)','EXECUTE') then
    raise exception 'Private helper execution is exposed.';
  end if;
end; $security$;
`
export function rehearsalSql(environment='staging', rollback=false) {
  let bootstrap=''
  if(environment==='production') {
    bootstrap=contracts.production.functions.map(f=>f.definition.trim()+';\n'+
      `revoke all on function ${f.name}(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean) from public,anon,authenticated,service_role;\n`+
      (f.name.startsWith('public.')?`grant execute on function ${f.name}(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean) to authenticated,service_role;`:'' )).join('\n')+
      '\ndrop function private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text);\n'
  }
  return `-- STAGING ONLY; production refers to source shape, NEVER the target project.
begin;
set local statement_timeout='180s';
${guard}
${bootstrap}
${inner(migrationSql())}
${restrict}
${existingScenarios()}
${read('supabase/staging/202609030107_pilot_issued_checkout_TEST.sql')}
${securityTests}
${rollback?inner(rollbackSql(environment)):''}
rollback;
select 'PASS 12 new-invoice + 15 issued-invoice scenarios; authenticated finance restrictions, four isolation/actor rejections and private-helper grants; all fixtures rolled back${rollback?'; code rollback rehearsed':''}.' as result;
`
}
