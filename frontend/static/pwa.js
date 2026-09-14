(() => {
  let installPrompt = null;
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installPrompt = event;
    window.dispatchEvent(new CustomEvent('pwa-installable'));
  });

  const supported = () => window.isSecureContext && 'serviceWorker' in navigator &&
    'PushManager' in window && 'Notification' in window;

  async function registration() {
    if (!supported()) throw new Error(window.isSecureContext ? 'unsupported' : 'insecure-context');
    await navigator.serviceWorker.register('/service-worker.js', { scope: '/' });
    return navigator.serviceWorker.ready;
  }

  function vapidBytes(value) {
    const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4);
    const raw = atob(padded);
    return Uint8Array.from([...raw].map((character) => character.charCodeAt(0)));
  }

  window.pwa217 = {
    async status() {
      let subscribed = false;
      if (supported()) {
        try {
          const reg = await registration();
          subscribed = Boolean(await reg.pushManager.getSubscription());
        } catch (_) {}
      }
      return JSON.stringify({
        supported: supported(),
        secure: window.isSecureContext,
        permission: 'Notification' in window ? Notification.permission : 'unsupported',
        subscribed,
        installable: Boolean(installPrompt),
        standalone: matchMedia('(display-mode: standalone)').matches
      });
    },
    async subscribe(publicKey) {
      if (!supported()) throw new Error(window.isSecureContext ? 'unsupported' : 'insecure-context');
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') throw new Error(permission === 'denied' ? 'permission-denied' : 'permission-not-granted');
      const reg = await registration();
      let subscription = await reg.pushManager.getSubscription();
      if (!subscription) {
        subscription = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: vapidBytes(publicKey)
        });
      }
      return JSON.stringify(subscription.toJSON());
    },
    async unsubscribe() {
      if (!supported()) return '';
      const reg = await registration();
      const subscription = await reg.pushManager.getSubscription();
      if (!subscription) return '';
      const endpoint = subscription.endpoint;
      await subscription.unsubscribe();
      return endpoint;
    },
    async install() {
      if (!installPrompt) return 'unavailable';
      installPrompt.prompt();
      const choice = await installPrompt.userChoice;
      installPrompt = null;
      return choice.outcome;
    },
    timezone() {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
    },
    localDate() {
      const now = new Date();
      const year = now.getFullYear();
      const month = String(now.getMonth() + 1).padStart(2, '0');
      const day = String(now.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    }
  };

  if ('serviceWorker' in navigator && window.isSecureContext) {
    navigator.serviceWorker.register('/service-worker.js', { scope: '/' }).catch(() => {});
  }
})();
