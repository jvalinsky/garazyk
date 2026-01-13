/**
 * Objective-C Code Execution Server
 * 
 * Provides a REST API for executing Objective-C code snippets
 * from the NSPds tutorial in a sandboxed Docker container.
 */

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { v4: uuidv4 } = require('uuid');
const { spawn } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3001;

// Configuration
const CONFIG = {
    maxCodeLength: 10 * 1024,  // 10KB max code size
    timeout: 5,                 // 5 seconds execution timeout
    maxConcurrent: 5,           // Max concurrent executions
    containerImage: 'objc-sandbox',
    dockerMemory: '128m',
    dockerCpus: '0.5',
    dockerPidsLimit: 50,
};

// Execution queue
let activeExecutions = 0;
const pendingQueue = [];

// Middleware
app.use(express.json({ limit: '16kb' }));
app.use(cors({
    origin: process.env.CORS_ORIGIN || '*',
    methods: ['POST', 'GET'],
}));

// Serve static files from public directory
const path = require('path');
app.use(express.static(path.join(__dirname, 'public')));

// Rate limiting: 10 requests per minute per IP
const limiter = rateLimit({
    windowMs: 60 * 1000,
    max: 10,
    message: { error: 'Too many requests. Please wait a minute.' },
    standardHeaders: true,
    legacyHeaders: false,
});

app.use('/api/', limiter);

// Root route
app.get('/', (req, res) => {
    res.json({
        name: 'Objective-C Code Runner',
        description: 'Execute Objective-C code snippets for the NSPds tutorial',
        endpoints: {
            'POST /api/execute': 'Run Objective-C code',
            'GET /health': 'Server status'
        }
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        activeExecutions,
        pendingQueue: pendingQueue.length
    });
});

// Execute code endpoint
app.post('/api/execute', async (req, res) => {
    const { code, timeout } = req.body;

    // Validate input
    if (!code || typeof code !== 'string') {
        return res.status(400).json({ error: 'Missing or invalid "code" field' });
    }

    if (code.length > CONFIG.maxCodeLength) {
        return res.status(400).json({
            error: `Code exceeds maximum length of ${CONFIG.maxCodeLength} bytes`
        });
    }

    const executionTimeout = Math.min(timeout || CONFIG.timeout, 10);
    const requestId = uuidv4();

    console.log(`[${requestId}] Received execution request (${code.length} bytes)`);

    try {
        const result = await executeCode(code, executionTimeout, requestId);
        res.json(result);
    } catch (error) {
        console.error(`[${requestId}] Execution error:`, error.message);
        res.status(500).json({
            error: 'Execution failed',
            message: error.message
        });
    }
});

/**
 * Execute Objective-C code in a sandboxed container
 */
async function executeCode(code, timeout, requestId) {
    // Wait for available slot
    if (activeExecutions >= CONFIG.maxConcurrent) {
        await waitForSlot();
    }

    activeExecutions++;
    console.log(`[${requestId}] Starting execution (active: ${activeExecutions})`);

    try {
        return await runContainer(code, timeout, requestId);
    } finally {
        activeExecutions--;
        processQueue();
    }
}

/**
 * Run code in Docker container
 */
function runContainer(code, timeout, requestId) {
    return new Promise((resolve, reject) => {
        const args = [
            'run', '--rm',
            '--network', 'none',
            '--memory', CONFIG.dockerMemory,
            '--cpus', CONFIG.dockerCpus,
            '--pids-limit', String(CONFIG.dockerPidsLimit),
            '--read-only',
            '--tmpfs', '/tmp:exec',
            '--tmpfs', '/run',
            '-e', `TIMEOUT=${timeout}`,
            '-i',  // Read from stdin
            CONFIG.containerImage
        ];

        const proc = spawn('docker', args);

        let stdout = '';
        let stderr = '';
        const startTime = Date.now();

        // Send code to container stdin
        proc.stdin.write(code);
        proc.stdin.end();

        proc.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        proc.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        // Overall timeout (Docker timeout + buffer)
        const overallTimeout = setTimeout(() => {
            proc.kill('SIGKILL');
            reject(new Error('Container execution timed out'));
        }, (timeout + 5) * 1000);

        proc.on('close', (exitCode) => {
            clearTimeout(overallTimeout);
            const executionTime = Date.now() - startTime;
            console.log(`[${requestId}] Completed in ${executionTime}ms`);

            // Parse JSON output from execute.sh
            try {
                const result = JSON.parse(stdout);
                resolve({
                    ...result,
                    requestId,
                    serverTime: executionTime
                });
            } catch (e) {
                // Fallback if JSON parsing fails
                resolve({
                    success: false,
                    phase: 'container',
                    exitCode,
                    stdout,
                    stderr,
                    requestId,
                    serverTime: executionTime
                });
            }
        });

        proc.on('error', (err) => {
            clearTimeout(overallTimeout);
            reject(err);
        });
    });
}

/**
 * Wait for an execution slot to become available
 */
function waitForSlot() {
    return new Promise((resolve) => {
        pendingQueue.push(resolve);
    });
}

/**
 * Process pending queue when a slot becomes available
 */
function processQueue() {
    if (pendingQueue.length > 0 && activeExecutions < CONFIG.maxConcurrent) {
        const next = pendingQueue.shift();
        next();
    }
}

// Error handling
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
    console.log(`🚀 Objective-C Runner listening on port ${PORT}`);
    console.log(`   Max concurrent: ${CONFIG.maxConcurrent}`);
    console.log(`   Timeout: ${CONFIG.timeout}s`);
    console.log(`   Rate limit: 10 req/min/IP`);
});

module.exports = app;
