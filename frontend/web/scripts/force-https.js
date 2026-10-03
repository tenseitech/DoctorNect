(function () {
  try {
    var host = location.hostname;
    var isLocal = host === 'localhost' || host === '127.0.0.1' || host === '';
    if (!isLocal && location.protocol === 'http:') {
      location.replace('https:' + window.location.href.substring(window.location.protocol.length));
    }
  } catch (e) {}
})();
