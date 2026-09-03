// Local browser fixture only. No credentials, authentication or external requests.
const mode = new URLSearchParams(location.search).get('mode') || 'paid'
let activeHotel = {id:'fixture-hotel',hotel_name:'LOCAL CHECKOUT FIXTURE',timezone:'Asia/Kolkata'}
const session = {id:'fixture-stay',hotel_id:'fixture-hotel',guest_id:'fixture-guest',room_id:'fixture-room',status:'active',
  checkin_time:new Date(Date.now()-3600000).toISOString(),checkout_time:new Date(Date.now()+3600000).toISOString(),
  guests:{id:'fixture-guest',full_name:'LOCAL TEST - no real guest',phone:''},
  rooms:{id:'fixture-room',room_number:'TEST-101',room_type:'Standard'}}
const complimentary = mode==='complimentary'
const total = complimentary ? 0 : 2240
const rows = {
  guest_sessions:[session],
  payments:[{id:'fixture-demand',hotel_id:'fixture-hotel',guest_session_id:session.id,guest_id:session.guest_id,
    room_id:session.room_id,payment_type:'room_charge',payment_status:'pending',amount:2500}],
  payment_collections:[],food_orders:[],manual_charges:[],service_requests:[],
  folios:[{id:'fixture-folio',hotel_id:'fixture-hotel',guest_session_id:session.id,charges_amount:2500,
    collection_amount:mode==='unpaid'?1000:total,refund_amount:0,credit_amount:0,balance_amount:mode==='unpaid'?1240:0}],
  invoices:mode==='new'?[]:[{id:'fixture-invoice',hotel_id:'fixture-hotel',guest_session_id:session.id,folio_id:'fixture-folio',
    invoice_number:'LOCAL-ISSUED-107',finalized_at:'2026-09-03',invoice_origin:'authoritative',metadata:{source:'folio'},
    subtotal_amount:complimentary?0:2000,discount_amount:complimentary?2500:500,discount_type:'fixed',
    discount_value:complimentary?2500:500,tax_amount:complimentary?0:240,tax_percent:complimentary?0:12,total_amount:total,
    pending_amount:total,paid_amount:0}]
}
export async function getCurrentHotel(){return activeHotel}
export function switchFakeHotel(){activeHotel={id:'other-fixture-hotel'};document.getElementById('fixture-state').textContent='Fake hotel switched'}
export const supabase={
  from(table){
    if(!(table in rows))throw new Error(`Unexpected local fixture table: ${table}`)
    let data=rows[table]
    let single=false
    const chain={
      select(){return chain},order(){return chain},limit(){return chain},gte(){return chain},
      eq(key,value){data=data.filter(row=>row[key]===value);return chain},
      in(key,values){data=data.filter(row=>values.includes(row[key]));return chain},
      maybeSingle(){single=true;return chain},
      then(resolve,reject){return Promise.resolve({data:single?data[0]??null:data,error:null}).then(resolve,reject)}
    }
    return chain
  },
  async rpc(name,args){
    if(name!=='checkout_guest_session')throw new Error(`Unexpected local fixture RPC: ${name}`)
    document.getElementById('fixture-requests').textContent=JSON.stringify({name,args})
    return {data:{success:true,invoice_id:'fixture-invoice',invoice_number:'LOCAL-ISSUED-107',grand_total:total,
      amount_collected_at_checkout:0,room_number:'TEST-101'},error:null}
  }
}
