const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const template = readFileSync(join(__dirname,'../AstonMobile5/GatewayPlayback.js'),'utf8');
function fixture() {
  const timers=[], events=[], clicks=[];
  const video={style:{},dataset:{},setAttribute(){},addEventListener(){}};
  const auth={style:{},classList:{contains:()=>true}};
  const status={style:{},textContent:''};
  const state={buttons:[],timers,events,clicks,video,auth};
  const document={body:{style:{},children:[auth,status,video],appendChild(){}},
    getElementById:id=>({video,authView:auth,status}[id]),querySelectorAll:selector=>{
      assert.equal(selector,'#channelRail [data-id]');return state.buttons;
    }};
  const context=vm.createContext({document,setTimeout:fn=>timers.push(fn),MutationObserver:class{observe(){}},
    window:{webkit:{messageHandlers:{videoState:{postMessage:x=>events.push(x)}}}}});
  state.run=(channel,requestId)=>vm.runInContext(template.replace('__ASTON_REQUEST__',JSON.stringify({channel,requestId})),context);
  state.add=id=>state.buttons.push({getAttribute:()=>id,click:()=>clicks.push(id)});
  state.drain=()=>{while(timers.length)timers.shift()();};
  assert.equal(vm.runInContext('typeof playback',context),'undefined');
  return state;
}
let f=fixture(); f.add('id:C501'); assert.equal(f.run('id:C501','a'),true); assert.deepEqual(f.clicks,['id:C501']);
f=fixture();f.run('delayed','a');f.add('delayed');f.drain();assert.deepEqual(f.clicks,['delayed']);
f=fixture();f.run('old','a');f.run('new','b');f.add('old');f.add('new');f.drain();assert.deepEqual(f.clicks,['new']);
f=fixture();f.run('missing','a');f.drain();assert.equal(f.events.at(-1).state,'missing-channel');
f=fixture();f.auth.classList.contains=()=>false;f.run('missing','a');f.drain();assert.equal(f.events.at(-1).state,'pairing');
f=fixture();const unusual='id:"quote\\and:colon';f.add(unusual);f.run(unusual,'a');assert.deepEqual(f.clicks,[unusual]);
console.log('6 Gateway bridge regression cases passed (private functions, async catalogue, cancellation, timeout, pairing, escaping)');
