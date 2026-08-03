const required = (name) => {
  const value = process.env[name]
  if (!value) throw new Error(`${name}-required`)
  return value
}

if (process.env.E2E_SALEOR_VERIFY !== 'saleor-e2e') {
  throw new Error('Refusing to run. Set E2E_SALEOR_VERIFY=saleor-e2e.')
}

const endpoint = required('SALEOR_E2E_API_URL')
const token = required('SALEOR_E2E_ADMIN_TOKEN')
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

let checkoutId
try {
  const variant = (await call(`query { productVariant(sku: "TH-E2E-TEST-001") { id channelListings { channel { slug } price { amount currency } } stocks { warehouse { slug } quantity } } }`)).productVariant
  if (!variant || variant.stocks.length !== 1 || variant.stocks[0].warehouse.slug !== 'terrahorse-e2e' || variant.stocks[0].quantity < 1 || !variant.channelListings.some((listing) => listing.channel.slug === 'terrahorse-e2e' && listing.price.amount === 10 && listing.price.currency === 'EUR')) throw new Error('e2e-variant-not-isolated')
  const created = await call(`mutation($input: CheckoutCreateInput!) { checkoutCreate(input: $input) { checkout { id } errors { code } } }`, { input: { channel: 'terrahorse-e2e', lines: [{ variantId: variant.id, quantity: 1 }] } })
  checkoutId = created.checkoutCreate.checkout?.id
  if (!checkoutId || created.checkoutCreate.errors.length) throw new Error('e2e-checkout-create-failed')
  const addressed = await call(`mutation($id: ID!, $shippingAddress: AddressInput!) { checkoutShippingAddressUpdate(id: $id, shippingAddress: $shippingAddress) { checkout { shippingMethods { id name } } errors { code } } }`, { id: checkoutId, shippingAddress: { firstName: 'E2E', lastName: 'Test', streetAddress1: 'E2E Test Boundary', city: 'Kaunas', postalCode: '00000', country: 'LT' } })
  const methods = addressed.checkoutShippingAddressUpdate.checkout?.shippingMethods ?? []
  if (addressed.checkoutShippingAddressUpdate.errors.length || methods.length !== 1 || methods[0].name !== 'TerraHorse E2E Test Delivery') throw new Error('e2e-delivery-not-isolated')
  const selected = await call(`mutation($id: ID!, $shippingMethodId: ID!) { checkoutShippingMethodUpdate(id: $id, shippingMethodId: $shippingMethodId) { errors { code } } }`, { id: checkoutId, shippingMethodId: methods[0].id })
  if (selected.checkoutShippingMethodUpdate.errors.length) throw new Error('e2e-delivery-select-failed')
  const reread = await call(`query($id: ID!) { checkout(id: $id) { deliveryMethod { ... on ShippingMethod { name } } } }`, { id: checkoutId })
  if (reread.checkout?.deliveryMethod?.name !== 'TerraHorse E2E Test Delivery') throw new Error('e2e-delivery-reread-failed')
} finally {
  if (checkoutId) {
    const deleted = await call(`mutation($id: ID!) { checkoutDelete(id: $id) { errors { code } } }`, { id: checkoutId })
    if (deleted.checkoutDelete.errors.length) throw new Error('e2e-checkout-delete-failed')
  }
}
process.stdout.write('E2E Saleor checkout delivery verified and cleaned up.\n')
