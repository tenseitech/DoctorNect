(function () {
  function removeLoader() {
    var loader = document.getElementById('dn-web-loader');
    if (loader) {
      loader.style.opacity = '0';
      setTimeout(function () {
        if (loader && loader.parentNode) loader.parentNode.removeChild(loader);
      }, 260);
    }
  }
  var observer = new MutationObserver(function () {
    if (document.querySelector('flutter-view, flt-glass-pane')) {
      removeLoader();
      observer.disconnect();
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
  window.addEventListener('flutter-first-frame', removeLoader);
})();
