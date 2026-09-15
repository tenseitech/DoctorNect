/** Lazy-load Razorpay checkout.js only when opening payments (not at app boot). */
window.loadRazorpayCheckout = function loadRazorpayCheckout() {
  if (window.Razorpay) {
    return Promise.resolve(window.Razorpay);
  }
  if (window.__razorpayCheckoutLoadPromise) {
    return window.__razorpayCheckoutLoadPromise;
  }
  window.__razorpayCheckoutLoadPromise = new Promise(function (resolve, reject) {
    var script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    script.onload = function () {
      if (window.Razorpay) {
        resolve(window.Razorpay);
      } else {
        reject(new Error('Razorpay checkout loaded but Razorpay global is missing.'));
      }
    };
    script.onerror = function () {
      reject(new Error('Failed to load Razorpay checkout.js'));
    };
    document.head.appendChild(script);
  });
  return window.__razorpayCheckoutLoadPromise;
};
