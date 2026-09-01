import { createClient } from 'npm:@supabase/supabase-js@2.106.2'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const originSet = () => new Set([Deno.env.get('STAYQR_APP_URL'), Deno.env.get('STAYQR_APP_URLS')].filter(Boolean).flatMap((v) => String(v).split(',')).map((v) => v.trim().replace(/\/$/, '')).filter(Boolean))
function cors(req: Request) { const origin=req.headers.get('Origin')||''; const allowed=originSet(); return {'Access-Control-Allow-Origin':allowed.has(origin)?origin:[...allowed][0]||origin||'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Max-Age':'86400',Vary:'Origin'} }
function json(req: Request,status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:{...cors(req),'Content-Type':'application/json','Cache-Control':'no-store'}})}
function uuid(value:unknown,label:string){const text=String(value||'').trim();if(!UUID.test(text))throw new Error(`${label} must be a valid UUID.`);return text}
function text(value:unknown){return String(value||'').trim()}

Deno.serve(async (request) => {
  if(request.method==='OPTIONS')return new Response('ok',{headers:cors(request)})
  if(request.method!=='POST')return json(request,405,{ok:false,error:'Method not allowed.'})
  let attemptId:string|null=null
  let requestId:string|null=null
  try{
    const url=Deno.env.get('SUPABASE_URL');const anon=Deno.env.get('SUPABASE_ANON_KEY');const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if(!url||!anon||!service)throw new Error('Supabase function environment is incomplete.')
    const bearer=(request.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'').trim();if(!bearer)return json(request,401,{ok:false,error:'Authentication is required.'})
    const auth=createClient(url,anon,{global:{headers:{Authorization:`Bearer ${bearer}`}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
    const {data:{user},error:userError}=await auth.auth.getUser(bearer);if(userError||!user)return json(request,401,{ok:false,error:'Your StayQR session is invalid or expired.'})
    const body=await request.json().catch(()=>({}));const hotelId=uuid(body.hotel_id,'hotel_id');const action=text(body.action).toLowerCase();requestId=body.request_id?uuid(body.request_id,'request_id'):null
    if(!['create','sync','upgrade','downgrade','cancel','reactivate','retry_payment','pause'].includes(action))throw new Error('Unsupported Cashfree recurring action.')
    const {data:permissionRows,error:permissionError}=await auth.rpc('get_my_hotel_permissions',{target_hotel_id:hotelId});if(permissionError)throw permissionError
    const permissions=new Set((permissionRows||[]).map((row:{permission_key?:string})=>row.permission_key));if(!permissions.has('hotel.manage')&&!permissions.has('payments.manage'))throw new Error('Owner billing management access denied.')
    if(requestId){const {data:ownerRequest,error:requestError}=await admin.from('owner_subscription_requests').select('id,hotel_id,action,status').eq('id',requestId).eq('hotel_id',hotelId).maybeSingle();if(requestError||!ownerRequest)throw new Error('Owner billing request was not found.');if(ownerRequest.status==='completed')return json(request,200,{ok:true,idempotent:true,status:'completed'})}
    const {data:readiness,error:readinessError}=await admin.from('platform_provider_readiness').select('status,environment,capabilities').eq('provider_key','cashfree_recurring').single();if(readinessError)throw readinessError
    if(readiness.status!=='active'||(Deno.env.get('CASHFREE_SUBSCRIPTIONS_ENABLED')||'').toLowerCase()!=='true'){
      if(requestId)await admin.from('owner_subscription_requests').update({status:'provider_activation_pending',updated_at:new Date().toISOString()}).eq('id',requestId)
      return json(request,409,{ok:false,code:'provider_activation_pending',error:'Cashfree recurring/AutoPay is not provider-enabled yet. The request is recorded without faking an active mandate.'})
    }
    const clientId=Deno.env.get('CASHFREE_CLIENT_ID');const clientSecret=Deno.env.get('CASHFREE_CLIENT_SECRET');const mode=(Deno.env.get('CASHFREE_MODE')||readiness.environment||'').toLowerCase();const apiVersion=Deno.env.get('CASHFREE_SUBSCRIPTIONS_API_VERSION')||'2026-01-01'
    if(!clientId||!clientSecret)throw new Error('Cashfree recurring credentials are incomplete.')
    const base=(mode==='test'||mode==='sandbox'?'https://sandbox.cashfree.com/pg':'https://api.cashfree.com/pg')
    const {data:subscription,error:subError}=await admin.from('hotel_subscriptions').select('*').eq('hotel_id',hotelId).in('status',['trial','trialing','active','past_due','suspended']).order('updated_at',{ascending:false}).limit(1).maybeSingle();if(subError||!subscription)throw new Error('No current hotel subscription was found.')
    const targetPlanId=body.plan_id?uuid(body.plan_id,'plan_id'):subscription.plan_id
    const {data:plan,error:planError}=await admin.from('subscription_plans').select('id,plan_name,plan_code,price_monthly,price_annual,currency_code,status').eq('id',targetPlanId).eq('status','active').single();if(planError||!plan)throw new Error('Active subscription plan was not found.')
    const cycle=body.billing_cycle==='annual'?'annual':'monthly';const amount=Number(cycle==='annual'?plan.price_annual:plan.price_monthly);if(!(amount>0))throw new Error('The selected recurring plan price is not configured.')
    const {data:priceMap,error:priceMapError}=await admin.from('subscription_plan_prices').select('provider_plan_id,status').eq('plan_id',targetPlanId).eq('provider','cashfree').eq('billing_cycle',cycle).eq('currency_code',plan.currency_code||'INR').maybeSingle();if(priceMapError)throw priceMapError
    const attemptType=action==='create'?'mandate_create':action==='retry_payment'?'retry':action==='upgrade'||action==='downgrade'?'change_plan':action
    const {data:attempt,error:attemptError}=await admin.from('subscription_recurring_attempts').insert({hotel_id:hotelId,subscription_id:subscription.id,owner_request_id:requestId,attempt_type:attemptType,amount_minor:Math.round(amount*100),currency_code:plan.currency_code||'INR',status:'processing',metadata:{action,cycle,api_version:apiVersion}}).select('id').single();if(attemptError)throw attemptError;attemptId=attempt.id
    if(requestId)await admin.from('owner_subscription_requests').update({status:'processing',updated_at:new Date().toISOString()}).eq('id',requestId)
    const headers={'Content-Type':'application/json','x-api-version':apiVersion,'x-client-id':clientId,'x-client-secret':clientSecret,'x-idempotency-key':crypto.randomUUID(),'x-request-id':crypto.randomUUID()}
    let endpoint='';let payload:Record<string,unknown>={};let providerSubscriptionId=subscription.provider_subscription_id
    if(action==='create'){
      const customer=body.customer||{};const customerName=text(customer.name);const customerEmail=text(customer.email);const customerPhone=text(customer.phone).replace(/\D/g,'')
      if(!customerName||!customerEmail||customerPhone.length<10)throw new Error('Owner name, email and phone are required to authorize AutoPay.')
      providerSubscriptionId=`stayqr_${hotelId.replace(/-/g,'').slice(0,16)}_${Date.now()}`
      endpoint='/subscriptions';payload={subscription_id:providerSubscriptionId,customer_details:{customer_name:customerName,customer_email:customerEmail,customer_phone:customerPhone},plan_details:{plan_name:`${plan.plan_code||plan.plan_name}_${cycle}`,plan_type:'PERIODIC',plan_amount:amount,plan_max_amount:amount,plan_max_cycles:120,plan_intervals:1,plan_currency:plan.currency_code||'INR',plan_interval_type:cycle==='annual'?'YEAR':'MONTH',plan_note:`StayQR ${plan.plan_name} ${cycle}`},authorization_details:{authorization_amount:1,authorization_amount_refund:true,payment_methods:['upi','enach','card']},subscription_meta:{return_url:`${Deno.env.get('STAYQR_APP_URL')||'https://app.stayqr.in'}/checkout/success`,notification_channel:['EMAIL','SMS']},subscription_tags:{stayqr_hotel_id:hotelId,stayqr_subscription_id:subscription.id}}
    }else if(action==='sync'){
      if(!providerSubscriptionId)throw new Error('No Cashfree recurring subscription exists to synchronize.');endpoint=`/subscriptions/${encodeURIComponent(providerSubscriptionId)}`
    }else if(action==='retry_payment'){
      if(!providerSubscriptionId)throw new Error('No active Cashfree mandate exists to retry.');endpoint='/subscriptions/pay';payload={subscription_id:providerSubscriptionId,payment_id:`retry_${subscription.id.replace(/-/g,'').slice(0,18)}_${Date.now()}`,payment_type:'CHARGE',payment_amount:amount,payment_schedule_date:new Date().toISOString(),payment_remarks:`StayQR retry for ${plan.plan_name}`}
    }else{
      if(!providerSubscriptionId)throw new Error('No Cashfree recurring subscription exists for this action.')
      const isPlanChange=action==='upgrade'||action==='downgrade'
      let planActionDetails:Record<string,unknown>={}
      if(isPlanChange){
        const providerPlanId=priceMap?.provider_plan_id
        if(!providerPlanId||priceMap?.status!=='active')throw new Error('The selected StayQR plan is not mapped to an active Cashfree recurring plan.')
        planActionDetails={action_details:{plan_id:providerPlanId}}
      }
      endpoint=`/subscriptions/${encodeURIComponent(providerSubscriptionId)}/manage`;const actionMap:Record<string,string>={upgrade:'CHANGE_PLAN',downgrade:'CHANGE_PLAN',cancel:'CANCEL',reactivate:'ACTIVATE',pause:'PAUSE'};payload={subscription_id:providerSubscriptionId,action:actionMap[action],...planActionDetails}
    }
    const providerResponse=await fetch(`${base}${endpoint}`,{method:action==='sync'?'GET':'POST',headers,body:action==='sync'?undefined:JSON.stringify(payload)});const providerBody=await providerResponse.json().catch(()=>({})) as Record<string,unknown>
    if(!providerResponse.ok){const providerError=(providerBody.error||providerBody) as Record<string,unknown>;throw Object.assign(new Error(text(providerError.message)||`Cashfree returned HTTP ${providerResponse.status}.`),{providerCode:text(providerError.code)||String(providerResponse.status),providerBody})}
    const providerStatus=text(providerBody.subscription_status||providerBody.status||providerBody.payment_status||'pending').toLowerCase();const authDetails=(providerBody.authorization_details||{}) as Record<string,unknown>;const authUrl=text(authDetails.authorization_link||providerBody.authorization_url||((providerBody.data as Record<string,unknown>|undefined)?.url));const providerEvidence={cf_subscription_id:text(providerBody.cf_subscription_id)||null,subscription_id:text(providerBody.subscription_id)||providerSubscriptionId,status:providerStatus,authorization_status:text(authDetails.authorization_status||providerBody.authorization_status)||null,cf_payment_id:text(providerBody.cf_payment_id)||null,payment_id:text(providerBody.payment_id)||null,next_schedule_date:text(providerBody.next_schedule_date)||null}
    const autopayStatus=['active','authenticated'].includes(providerStatus)?'active':action==='cancel'?'cancelled':action==='pause'?'paused':action==='create'?'authorization_pending':subscription.autopay_status
    await admin.from('hotel_subscriptions').update({provider:'cashfree',provider_subscription_id:providerSubscriptionId,provider_status:providerStatus,autopay_status:autopayStatus,mandate_id:text(providerBody.cf_subscription_id||providerBody.mandate_id)||subscription.mandate_id,mandate_status:text(authDetails.authorization_status||providerBody.authorization_status)||subscription.mandate_status,next_charge_at:providerBody.next_schedule_date||subscription.next_charge_at,last_charge_status:action==='retry_payment'?providerStatus:subscription.last_charge_status,last_charge_at:action==='retry_payment'?new Date().toISOString():subscription.last_charge_at,recurring_failure_code:null,recurring_failure_message:null,...(action==='upgrade'||action==='downgrade'?{plan_id:targetPlanId,billing_cycle:cycle,amount_minor:Math.round(amount*100),currency_code:plan.currency_code||'INR'}:{}),provider_metadata:{...(subscription.provider_metadata||{}),cashfree_recurring_last_evidence:providerEvidence,cashfree_recurring_synced_at:new Date().toISOString()},updated_at:new Date().toISOString()}).eq('id',subscription.id)
    await admin.from('subscription_recurring_attempts').update({status:'succeeded',provider_payment_id:text(providerBody.cf_payment_id||providerBody.payment_id)||null,completed_at:new Date().toISOString(),metadata:{action,provider_status:providerStatus}}).eq('id',attemptId)
    if(requestId)await admin.from('owner_subscription_requests').update({status:'completed',provider_request_id:text(providerBody.cf_subscription_id||providerBody.cf_payment_id)||providerSubscriptionId,completed_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('id',requestId)
    return json(request,200,{ok:true,status:providerStatus,autopay_status:autopayStatus,authorization_url:/^https:\/\//i.test(authUrl)?authUrl:null,provider_subscription_id:providerSubscriptionId})
  }catch(error){
    const message=error instanceof Error?error.message:'Unexpected Cashfree recurring error.';const code=text((error as Record<string,unknown>)?.providerCode)||'cashfree_recurring_error'
    try{const url=Deno.env.get('SUPABASE_URL');const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');if(url&&service){const admin=createClient(url,service,{auth:{persistSession:false}});if(attemptId)await admin.from('subscription_recurring_attempts').update({status:'failed',failure_code:code,failure_message:message.slice(0,500),completed_at:new Date().toISOString()}).eq('id',attemptId);if(requestId)await admin.from('owner_subscription_requests').update({status:'failed',failure_code:code,failure_message:message.slice(0,500),updated_at:new Date().toISOString()}).eq('id',requestId)}}catch{/* best-effort failure evidence */}
    return json(request,400,{ok:false,error:message,code})
  }
})
