(function (root) {
  'use strict';
  function install(canvas) {
    canvas.addEventListener('wheel', function (event) {
      if (event.ctrlKey) return;
      canvas.focus({preventScroll:true});
      event.preventDefault();
    }, {capture:true, passive:false});
  }
  if (typeof module === 'object') module.exports = {install};
  else root.MagicStoreWheel = {install};
})(typeof globalThis === 'object' ? globalThis : this);
