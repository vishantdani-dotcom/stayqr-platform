/* StayQR background push service worker.
 * Deliberately has no fetch/cache handler so it cannot alter the locked app shell.
 */

self.addEventListener('push', (event) => {
  let payload

  try {
    payload = event.data?.json?.() || {}
  } catch {
    payload = {
      title: 'StayQR',
      body: event.data?.text?.() || 'New hotel activity',
    }
  }

  const title = String(payload.title || 'StayQR')
  const body = String(payload.body || 'New hotel activity')
  const data = payload.data && typeof payload.data === 'object'
    ? payload.data
    : {}

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/assets/stayqr-push-192.png',
      badge: '/assets/stayqr-push-badge-96.png',
      tag: String(payload.tag || data.recipient_id || 'stayqr-activity'),
      renotify: Boolean(payload.renotify),
      requireInteraction: Boolean(payload.requireInteraction),
      data,
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const requestedUrl = String(
    event.notification?.data?.url || '/?stayqr_push=1&section=operationscenter'
  )
  const targetUrl = new URL(requestedUrl, self.location.origin).href

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(async (windowClients) => {
        const sameOriginClient = windowClients.find((client) => {
          try {
            return new URL(client.url).origin === self.location.origin
          } catch {
            return false
          }
        })

        if (sameOriginClient) {
          sameOriginClient.postMessage({
            type: 'STAYQR_PUSH_NAVIGATE',
            url: targetUrl,
          })
          await sameOriginClient.focus()
          return
        }

        await self.clients.openWindow(targetUrl)
      })
  )
})

self.addEventListener('pushsubscriptionchange', (event) => {
  // A refreshed browser subscription is reconciled the next time the user opens
  // My Profile. Never create an unauthenticated server binding in the worker.
  event.waitUntil(Promise.resolve())
})
