const http = require('http');

const server = http.createServer((req, res) => {
  res.end('API rodando via systemd e com github actions, em produção!');
});

server.listen(3001, '127.0.0.1', () => {
  console.log('API na porta 3001');
});
