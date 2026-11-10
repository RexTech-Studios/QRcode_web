// LOCAL TEST BUILD ONLY. start-local.ps1 copies this next to build/web_local and
// loads it before the app. It is never part of the real site (web/index.html
// does not reference it).
//
// Why it exists: on a page reload Firebase Auth re-checks the saved sign-in
// straight away, before the app has told it to use the local emulator. That
// check went to Google's REAL servers, which rejected the fake local login, so
// every reload signed you out and the next sign-in also went to the real
// servers ("Incorrect email or password"). Here every Auth call is sent to the
// emulator instead, whatever the order things start in.
(function () {
  var EMULATOR = 'http://localhost:9099/';
  var HOSTS = ['identitytoolkit.googleapis.com', 'securetoken.googleapis.com'];

  function redirect(raw) {
    try {
      var url = new URL(raw, location.href);
      if (HOSTS.indexOf(url.hostname) !== -1) {
        return EMULATOR + url.hostname + url.pathname + url.search;
      }
    } catch (e) {
      /* not a URL we can parse: leave it alone */
    }
    return raw;
  }

  var realFetch = window.fetch;
  window.fetch = function (input, init) {
    if (typeof input === 'string') return realFetch.call(this, redirect(input), init);
    if (input instanceof URL) return realFetch.call(this, redirect(input.href), init);
    if (input && typeof input.url === 'string') {
      var target = redirect(input.url);
      if (target !== input.url) {
        return realFetch.call(this, new Request(target, input), init);
      }
    }
    return realFetch.call(this, input, init);
  };
})();
