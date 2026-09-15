async function startFlutter() {
  if (window.__firebaseSdkReady) {
    try {
      await window.__firebaseSdkReady;
    } catch (e) {
      console.error('Firebase SDK preload failed:', e);
    }
  }

  var s = document.createElement('script');
  s.src = 'flutter_bootstrap.js';
  s.async = true;
  document.body.appendChild(s);
}

window.addEventListener('flutter-first-frame', function () {
  var splash = document.getElementById('app-loading-splash');
  if (splash) {
    splash.style.opacity = '0';
    setTimeout(function () {
      splash.remove();
    }, 400);
  }
});

setTimeout(function () {
  var splash = document.getElementById('app-loading-splash');
  if (splash && splash.parentNode) {
    splash.style.opacity = '0';
    setTimeout(function () {
      if (splash.parentNode) splash.remove();
    }, 400);
  }
}, 6000);

startFlutter();
