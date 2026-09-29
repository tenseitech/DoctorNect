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

startFlutter();
