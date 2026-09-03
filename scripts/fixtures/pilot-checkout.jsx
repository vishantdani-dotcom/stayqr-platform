import { createRoot } from 'react-dom/client'
import Guests from '../../src/pages/guests/Guests'
import { switchFakeHotel } from './pilot-checkout-mock.mjs'

createRoot(document.getElementById('root')).render(<>
  <aside style={{padding:16,background:'#fff3cd',color:'#000'}}>
    <strong>LOCAL CHECKOUT FIXTURE — real Guests component, synthetic data, no server writes</strong>
    <p><a href="?mode=paid">Paid issued invoice</a> | <a href="?mode=unpaid">Unpaid issued invoice</a> | <a href="?mode=complimentary">Complimentary issued invoice</a> | <a href="?mode=new">New invoice</a></p>
    <button onClick={switchFakeHotel}>Switch fake hotel</button>
    <span id="fixture-state">Original fake hotel</span>
    <pre id="fixture-requests">No checkout requests</pre>
  </aside>
  <Guests />
</>)
