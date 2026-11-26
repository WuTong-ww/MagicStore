const assert = require('node:assert/strict');
const wheel = require('../../web/wheel-focus.js');
let handler, options, focused=false, blocked=0, checks=0;
const check=(actual,expected)=>{assert.deepEqual(actual,expected); checks++;};
const canvas={
  width:2560,height:1058,
  getBoundingClientRect(){return {left:10,top:20,width:1280,height:529};},
  addEventListener(name,callback,opts){check(name,'wheel'); handler=callback; options=opts;},
  focus(opts){check(opts,{preventScroll:true}); focused=true;}
};
wheel.install(canvas);
check(options,{capture:true,passive:false});
let received=[];
const sink=(x,y)=>{check(focused,true); received.push([x,y]);};
wheel.bindPointer(sink);
for (const deltaY of [-120,120]) {
  focused=false;
  handler({clientX:410,clientY:220,deltaY,ctrlKey:false,preventDefault(){blocked++;}});
  check(focused,true);
}
check(received,[[800,400],[800,400]]); // CSS offset and device pixel ratio.
focused=false;
handler({ctrlKey:true,preventDefault(){throw Error('browser zoom intercepted');}});
check(focused,false);
check(received.length,2);
wheel.unbindPointer(()=>{}); // An obsolete owner cannot disconnect the new owner.
handler({clientX:110,clientY:120,preventDefault(){blocked++;}});
check(received.at(-1),[200,200]);
wheel.unbindPointer(sink);
handler({clientX:110,clientY:120,preventDefault(){blocked++;}});
check(received.length,3);
wheel.bindPointer(sink);
canvas.width=NaN;
handler({clientX:110,clientY:120,preventDefault(){blocked++;}});
check(received.length,3);
check(blocked,5);
console.log(`WEB WHEEL: ${checks} checks, 0 failures`);
