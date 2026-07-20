// SAFEBOAT — Âncora Virtual — servidor estático do protótipo (porta 8101)
const http = require('http')
const fs = require('fs')
const path = require('path')

const PORT = 8101
const ROOT = __dirname
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.json': 'application/json',
}

http.createServer((req, res) => {
  let url = decodeURIComponent(req.url.split('?')[0])
  if (url === '/') url = '/index.html'
  // /core/* servido da pasta core/ (núcleo + simulação), resto de public/
  const base = url.startsWith('/core/') ? ROOT : path.join(ROOT, 'public')
  const file = path.normalize(path.join(base, url))
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end('404')
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' })
  fs.createReadStream(file).pipe(res)
}).listen(PORT, () => console.log(`SAFEBOAT Âncora Virtual: http://localhost:${PORT}`))
