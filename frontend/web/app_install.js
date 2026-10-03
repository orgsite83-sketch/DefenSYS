// Capture early: the install event can arrive before Flutter finishes loading.
(() => {
  let pendingPrompt = null;
  let installed = false;
  const standalone = window.matchMedia('(display-mode: standalone)');
  const notify = () => window.dispatchEvent(new Event('defensys-install-state'));
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    pendingPrompt = event;
    notify();
  });
  window.addEventListener('appinstalled', () => {
    installed = true;
    pendingPrompt = null;
    notify();
  });
  standalone.addEventListener('change', notify);
  window.defensysInstallation = {
    state() {
      const ua = navigator.userAgent;
      const ios = /iPad|iPhone|iPod/.test(ua) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      return JSON.stringify({
        platform: ios ? 'ios' : /Android/i.test(ua) ? 'android' : 'desktop',
        isWeb: true,
        installed: installed || standalone.matches || navigator.standalone === true,
        canPrompt: pendingPrompt !== null,
        secure: window.isSecureContext,
      });
    },
    async install() {
      const event = pendingPrompt;
      if (!event) return 'unavailable';
      pendingPrompt = null;
      notify();
      try {
        await event.prompt();
        const choice = await event.userChoice;
        return choice.outcome;
      } catch (_) {
        return 'unavailable';
      }
    },
  };
})();
