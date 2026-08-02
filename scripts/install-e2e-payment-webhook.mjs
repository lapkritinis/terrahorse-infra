import { readFileSync } from 'node:fs'

const required = (name) => {
  const value = process.env[name]
  if (!value) throw new Error(`${name}-required`)
  return value
}
const endpoint = required('SALEOR_E2E_API_URL')
const token = required('SALEOR_E2E_ADMIN_TOKEN')
const secret = required('SALEOR_PAYMENT_WEBHOOK_SECRET')
const source = readFileSync(required('E2E_STOREFRONT_PAYMENT_OPERATION'), 'utf8')
const subscription = source.slice(source.indexOf('fragment SaleorTransactionInitializeSessionEvent'), source.indexOf('mutation SaleorPaymentOwnershipPrivateMetadataUpdate'))
const call = async (query, variables = {}) => {
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ query, variables }) })
  const body = await response.json()
  if (!response.ok || body.errors?.length) throw new Error('saleor-graphql-failure')
  return body.data
}
const read = `query { app { id name webhooks { id name isActive targetUrl subscriptionQuery app { id } syncEvents { eventType } asyncEvents { eventType } } } }`
const app = (await call(read)).app
if (app.name !== 'TerraHorse E2E Provisioner') throw new Error('unexpected-e2e-app')
const matches = app.webhooks.filter((webhook) => webhook.name === 'TerraHorse transaction initialize')
if (matches.length > 1 || matches.some((webhook) => webhook.app.id !== app.id)) throw new Error('foreign-or-duplicate-webhook')
const input = { app: app.id, name: 'TerraHorse transaction initialize', isActive: true, targetUrl: 'https://e2e.terrahorse.lt/api/payments/saleor/initialize', secretKey: secret, syncEvents: ['TRANSACTION_INITIALIZE_SESSION'], asyncEvents: [], query: subscription }
const result = matches.length ? await call(`mutation($id: ID!, $input: WebhookUpdateInput!) { webhookUpdate(id: $id, input: $input) { errors { code } } }`, { id: matches[0].id, input }) : await call(`mutation($input: WebhookCreateInput!) { webhookCreate(input: $input) { errors { code } } }`, { input })
if ((matches.length ? result.webhookUpdate : result.webhookCreate).errors.length) throw new Error('payment-webhook-write-failed')
const [webhook] = (await call(read)).app.webhooks.filter((candidate) => candidate.name === input.name)
if (!webhook || webhook.app.id !== app.id || !webhook.isActive || webhook.targetUrl !== input.targetUrl || webhook.syncEvents.map(({ eventType }) => eventType).join() !== 'TRANSACTION_INITIALIZE_SESSION' || webhook.asyncEvents.length || webhook.subscriptionQuery.replace(/\s+/g, ' ').trim() !== subscription.replace(/\s+/g, ' ').trim()) throw new Error('payment-webhook-reread-failed')
console.log('E2E payment webhook verified.')
