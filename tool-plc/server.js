const { PlcServer, Database } = require('@did-plc/server');
const getPort = require('get-port');

async function start() {
    try {
        const db = Database.mock();
        const port = parseInt(process.env.PORT || '2582');

        const server = PlcServer.create({
            db,
            port
        });

        await server.start();
        console.log(`PLC Server running at http://localhost:${port}`);
        console.log(`NOTE: This server uses in-memory storage. Data will be lost on restart.`);

        // Graceful shutdown
        process.on('SIGTERM', async () => {
            await server.destroy();
            process.exit(0);
        });

    } catch (err) {
        console.error('Failed to start PLC server:', err);
        process.exit(1);
    }
}

start();
