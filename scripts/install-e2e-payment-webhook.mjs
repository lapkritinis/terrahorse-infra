import { readFileSync } from 'node:fs'

const required = (name) => {
  const value = process.env[name]
  if (!value) throw new Error(`${name}-required`)
  return value
}
const endpoint = required('SALEOR_E2E_API_URL')
const token = required('SALEOR_E2E_ADMIN_TOKEN')
const normalize = (value) => value.replace(/\s+/g, ' ').trim()
const emptyHeaders = (value) => {
  if (value == null || value === '') return true
  const parsed = typeof value === 'string' ? JSON.parse(value) : value
  return parsed && typeof parsed === 'object' && !Array.isArray(parsed) && Object.keys(parsed).length === 0
}
const call = async (query, variables = {}) => {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ query, variables })
  })
  const body = await response.json()
  if (!response.ok || body.errors?.length) throw new Error('saleor-graphql-failure')
  return body.data
}
const read = `query { app { id name isActive permissions { code } webhooks { id name isActive targetUrl customHeaders subscriptionQuery app { id } syncEvents { eventType } asyncEvents { eventType } } } }`
const readApp = async () => (await call(read)).app
const validateIdentity = (app) => {
  if (!app || app.name !== 'TerraHorse E2E Provisioner') throw new Error('unexpected-e2e-app')
  if (!app.isActive) throw new Error('inactive-e2e-app')
  if (!app.permissions.some(({ code }) => code === 'HANDLE_PAYMENTS')) throw new Error('handle-payments-permission-required')
}

const app = await readApp()
validateIdentity(app)
if (process.env.E2E_WEBHOOK_IDENTITY_ONLY === 'terrahorse-e2e') {
  process.stdout.write(app.id)
  process.exit(0)
}
if (process.env.E2E_WEBHOOK_INSTALL_CONFIRM !== 'terrahorse-e2e') {
  throw new Error('e2e-webhook-confirmation-required')
}
const configuredAppId = required('SALEOR_PAYMENT_APP_ID')
if (app.id !== configuredAppId) throw new Error('configured-app-id-mismatch')
const secret = required('SALEOR_PAYMENT_WEBHOOK_SECRET')
const source = readFileSync(required('E2E_STOREFRONT_PAYMENT_OPERATION'), 'utf8')
const start = source.indexOf('fragment SaleorTransactionInitializeSessionEvent')
const end = source.indexOf('mutation SaleorPaymentOwnershipPrivateMetadataUpdate')
if (start < 0 || end <= start) throw new Error('payment-subscription-not-found')
const subscription = source.slice(start, end).trim()
const name = 'TerraHorse transaction initialize'
const matches = app.webhooks.filter((webhook) => webhook.name === name)
if (matches.length > 1 || matches.some((webhook) => webhook.app.id !== app.id)) {
  throw new Error('foreign-or-duplicate-webhook')
}
const input = {
  app: app.id,
  name,
  isActive: true,
  targetUrl: 'https://e2e.terrahorse.lt/api/payments/saleor/initialize',
  secretKey: secret,
  syncEvents: ['TRANSACTION_INITIALIZE_SESSION'],
  asyncEvents: [],
  customHeaders: '{}',
  query: subscription
}
const result = matches.length
  ? await call(`mutation($id: ID!, $input: WebhookUpdateInput!) { webhookUpdate(id: $id, input: $input) { errors { code } } }`, { id: matches[0].id, input })
  : await call(`mutation($input: WebhookCreateInput!) { webhookCreate(input: $input) { errors { code } } }`, { input })
const errors = (matches.length ? result.webhookUpdate : result.webhookCreate).errors
if (errors.length) throw new Error('payment-webhook-write-failed')

const reread = await readApp()
validateIdentity(reread)
if (reread.id !== configuredAppId) throw new Error('configured-app-id-mismatch')
const rereadMatches = reread.webhooks.filter((webhook) => webhook.name === name)
if (rereadMatches.length !== 1) throw new Error('payment-webhook-count-mismatch')
const [webhook] = rereadMatches
if (
  webhook.app.id !== reread.id || webhook.name !== name || !webhook.isActive ||
  webhook.targetUrl !== input.targetUrl ||
  webhook.syncEvents.length !== 1 || webhook.syncEvents[0].eventType !== 'TRANSACTION_INITIALIZE_SESSION' ||
  webhook.asyncEvents.length !== 0 || !emptyHeaders(webhook.customHeaders) ||
  normalize(webhook.subscriptionQuery) !== normalize(subscription)
) throw new Error('payment-webhook-reread-failed')

process.stdout.write('E2E payment webhook contract verified.\n')
