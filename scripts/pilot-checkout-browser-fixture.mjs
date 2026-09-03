import { createServer } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
const mock=fileURLToPath(new URL('./fixtures/pilot-checkout-mock.mjs',import.meta.url))
const server=await createServer({configFile:false,plugins:[{
  name:'local-checkout-no-network-fixture',enforce:'pre',
  resolveId(source){
    if(/(?:^|\/)(?:supabase|currentHotel)(?:\.js)?$/.test(source))return mock
  }
},react()],server:{host:'127.0.0.1',port:5176,strictPort:true}})
await server.listen()
console.log('Local-only checkout fixture: http://127.0.0.1:5176/scripts/fixtures/pilot-checkout.html')
