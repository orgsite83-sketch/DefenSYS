{{flutter_js}}
{{flutter_build_config}}

// Uploaded release files already revalidate through Nginx. Retire Flutter's
// legacy offline cache so ordinary reloads can use the currently deployed app.
(async () => {
  try {
    if ('serviceWorker' in navigator) {
      const script = new URL('flutter_service_worker.js', document.baseURI);
      const registrations = await navigator.serviceWorker.getRegistrations();
      let retired = false;
      for (const registration of registrations) {
        const workers = [registration.active, registration.waiting, registration.installing];
        if (workers.some((worker) => {
          if (!worker) return false;
          const url = new URL(worker.scriptURL);
          return url.origin === script.origin && url.pathname === script.pathname;
        })) {
          await registration.unregister();
          retired = true;
        }
      }
      if (retired && 'caches' in window) {
        await Promise.all(
          ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']
            .map((name) => caches.delete(name)),
        );
      }
    }
  } catch (error) {
    // A browser storage restriction must not prevent login from loading.
    console.warn('Could not retire the previous Flutter cache:', error);
  }
  await _flutter.loader.load();
})();
