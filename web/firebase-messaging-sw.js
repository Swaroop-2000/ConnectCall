importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: 'AIzaSyASPhYJM_iPfrSad_0g9cx-BgJsb_13RlI',
    appId: '1:674297555728:web:e6ad856920729c9fab5395',
    messagingSenderId: '674297555728',
    projectId: 'eye-disease-prediction-5b87a',
    authDomain: 'eye-disease-prediction-5b87a.firebaseapp.com',
    storageBucket: 'eye-disease-prediction-5b87a.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // FCM automatically shows a notification if the payload contains a 'notification' object.
  // We don't need to manually show it here, otherwise it duplicates!
  /*
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };
  self.registration.showNotification(notificationTitle, notificationOptions);
  */
});

// Handle clicking on the notification
self.addEventListener('notificationclick', (event) => {
    event.notification.close();

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
            // Find an open window and focus it
            for (let i = 0; i < windowClients.length; i++) {
                const client = windowClients[i];
                if (client.url && 'focus' in client) {
                    return client.focus();
                }
            }
            // If no window is open, open a new one
            if (clients.openWindow) {
                return clients.openWindow('/');
            }
        })
    );
});
