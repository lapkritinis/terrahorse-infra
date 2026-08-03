import { readFileSync } from 'node:fs'

const [configPath, credentialsPath] = process.argv.slice(2)
if (!configPath || !credentialsPath) throw new Error('tunnel-config-inputs-required')
const uuid = JSON.parse(readFileSync(credentialsPath, 'utf8')).TunnelID
if (!/^[0-9a-f-]{36}$/i.test(uuid)) throw new Error('invalid-tunnel-identity')
const actual = readFileSync(configPath, 'utf8').split(/\r?\n/).map((line) => line.trim()).filter((line) => line && !line.startsWith('#'))
const expected = [`tunnel: ${uuid}`, 'credentials-file: /etc/cloudflared/credentials.json', 'loglevel: info', 'ingress:',
  '- hostname: e2e.terrahorse.lt', 'service: http://host.docker.internal:4100', '- service: http_status:404']
if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error('unexpected-e2e-tunnel-config')
