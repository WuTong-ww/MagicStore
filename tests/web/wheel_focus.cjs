const assert = require('node:assert/strict');
const wheel = require('../../web/wheel-focus.js');
let handler, options, focused=false, blocked=0;
wheel.install({addEventListener(name, callback, opts) { assert.equal(name,'wheel'); handler=callback; options=opts; },focus(opts) { assert.deepEqual(opts,{preventScroll:true}); focused=true; }});
assert.deepEqual(options,{capture:true,passive:false});
for (const deltaY of [-120,120]) {
  focused=false;
  handler({deltaY,ctrlKey:false,preventDefault(){blocked++;}});
  assert.equal(focused,true);
}
focused=false;
handler({ctrlKey:true,preventDefault(){throw Error('browser zoom intercepted');}});
assert.equal(focused,false);
assert.equal(blocked,2);
console.log('WEB WHEEL: 9 checks, 0 failures');
