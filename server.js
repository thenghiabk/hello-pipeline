const http = require('http');

const APP_ENV = process.env.APP_ENV || 'development';
const VERSION = process.env.VERSION || 'dev';
const PORT = process.env.PORT || 3000;

function createServer() {
    return http.createServer((req, res) => {
        if (req.url === '/health') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ status: 'ok', }));
        }

        res.writeHead(200, { 'Content-Type': 'text/plain; charset: utf-8' });
        res.end(`Hello World again! Environment: ${APP_ENV} | Version: ${VERSION}\n`);
    });
}

if (require.main === module) {
    createServer().listen(PORT, () => {
        console.log(`Server running at port ${PORT} in ${APP_ENV} environment with version ${VERSION}`);
    });
}

module.exports = createServer;