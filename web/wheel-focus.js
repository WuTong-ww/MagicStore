(function (root) {
  'use strict';
  let pointerSink = null;
  function bindPointer(callback) { pointerSink = callback; }
  function unbindPointer(callback) { if (pointerSink === callback) pointerSink = null; }
  function install(canvas) {
    canvas.addEventListener('wheel', function (event) {
      if (event.ctrlKey) return;
      canvas.focus({preventScroll:true});
      if (pointerSink) {
        const rect = canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) * canvas.width / rect.width;
        const y = (event.clientY - rect.top) * canvas.height / rect.height;
        if (Number.isFinite(x) && Number.isFinite(y)) pointerSink(x, y);
      }
      event.preventDefault();
    }, {capture:true, passive:false});
  }
  const api = {install, bindPointer, unbindPointer};
  if (typeof module === 'object') module.exports = api;
  else root.MagicStoreWheel = api;
})(typeof globalThis === 'object' ? globalThis : this);
