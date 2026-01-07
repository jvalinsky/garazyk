import express, { Request, Response, NextFunction } from 'express';
import { Pool } from 'pg';
import crypto from 'crypto';

const app = express();
app.use(express.json());

const PORT = process.env.PORT || '2582';
const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://plc:plc_secret@localhost:5432/plc?sslmode=disable';

const pool = new Pool({
  connectionString: DATABASE_URL,
});

interface PlcOperation {
  type: 'create' | 'update' | 'rotate_key' | 'deactivate';
  did?: string;
  handle?: string;
  signer: {
    did: string;
    keyId: string;
  };
  prev?: string;
  signingKey: string;
  rotationKeys: string[];
  services?: Record<string, { type: string; endpoint: string }>;
}

function hashOperation(op: PlcOperation): string {
  const opCopy = { ...op };
  delete (opCopy as any).signer;
  const data = JSON.stringify(opCopy);
  return crypto.createHash('sha256').update(data).digest('hex');
}

function generateDid(op: PlcOperation): string {
  const hash = hashOperation(op);
  const did = `did:plc:${hash.substring(0, 24)}`;
  return did;
}

async function initializeDatabase() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS rotation_key (
        id TEXT PRIMARY KEY,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        owner TEXT NOT NULL REFERENCES repo(id),
        public_key bytea NOT NULL
      );

      CREATE TABLE IF NOT EXISTS repo (
        id TEXT PRIMARY KEY,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        null_hash bytea NOT NULL,
        current TEXT NOT NULL,
        history TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS operation (
        id BIGSERIAL PRIMARY KEY,
        repo TEXT NOT NULL REFERENCES repo(id),
        operation JSONB NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        signed_at TIMESTAMP WITH TIME ZONE,
        prev bytea NOT NULL,
        sig bytea NOT NULL,
        key_id TEXT NOT NULL REFERENCES rotation_key(id)
      );

      CREATE INDEX IF NOT EXISTS operation_repo_idx ON operation(repo);
      CREATE INDEX IF NOT EXISTS operation_created_at_idx ON operation(created_at);
      CREATE INDEX IF NOT EXISTS repo_current_idx ON repo(current);
      CREATE INDEX IF NOT EXISTS rotation_key_owner_idx ON rotation_key(owner);
    `);
    console.log('Database initialized successfully');
  } finally {
    client.release();
  }
}

app.get('/xrpc/_health', async (req: Request, res: Response) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (error) {
    res.status(503).json({ status: 'error', error: 'Database not available' });
  }
});

app.post('/xrpc/plc.createAccount', async (req: Request, res: Response) => {
  const client = await pool.connect();
  try {
    const { rotationKeys, signingKey, handle, services } = req.body;

    if (!rotationKeys || !signingKey || !handle) {
      return res.status(400).json({
        error: 'InvalidRequest',
        message: 'Missing required fields: rotationKeys, signingKey, handle'
      });
    }

    const op: PlcOperation = {
      type: 'create',
      handle,
      signer: { did: '', keyId: '' },
      signingKey,
      rotationKeys,
      services: services || {}
    };

    const did = generateDid(op);
    op.did = did;

    const nullHash = crypto.createHash('sha256').update('null').digest('hex');

    await client.query('BEGIN');

    await client.query(
      `INSERT INTO repo (id, null_hash, current, history)
       VALUES ($1, $2, $3, $4)`,
      [did, Buffer.from(nullHash, 'hex'), did, did]
    );

    for (const key of rotationKeys) {
      await client.query(
        `INSERT INTO rotation_key (id, owner, public_key)
         VALUES ($1, $2, $3)`,
        [key, did, Buffer.from(key, 'hex')]
      );
    }

    const opJson = JSON.stringify(op);
    await client.query(
      `INSERT INTO operation (repo, operation, prev, sig, key_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [did, opJson, Buffer.from(nullHash, 'hex'), Buffer.from('sig', 'hex'), rotationKeys[0]]
    );

    await client.query('COMMIT');

    res.json({
      did,
      rotationKeys,
      signingKey,
      handle
    });
  } catch (error: any) {
    await client.query('ROLLBACK');
    console.error('Error creating account:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  } finally {
    client.release();
  }
});

app.post('/xrpc/plc.updateAccount', async (req: Request, res: Response) => {
  const client = await pool.connect();
  try {
    const { did, rotationKeys, signingKey, handle, services, prev } = req.body;

    if (!did) {
      return res.status(400).json({
        error: 'InvalidRequest',
        message: 'Missing did'
      });
    }

    const op: PlcOperation = {
      type: 'update',
      did,
      handle,
      signer: { did, keyId: '' },
      signingKey,
      rotationKeys,
      prev,
      services: services || {}
    };

    const opJson = JSON.stringify(op);
    const prevBuffer = prev ? Buffer.from(prev, 'hex') : Buffer.from('null', 'hex');

    await client.query('BEGIN');

    await client.query(
      `INSERT INTO operation (repo, operation, prev, sig, key_id)
       VALUES ($1, $2, $3, $4, $5)`,
      [did, opJson, prevBuffer, Buffer.from('sig', 'hex'), rotationKeys?.[0] || '']
    );

    await client.query('COMMIT');

    res.json({ success: true, did });
  } catch (error: any) {
    await client.query('ROLLBACK');
    console.error('Error updating account:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  } finally {
    client.release();
  }
});

app.get('/xrpc/plc.getAccount', async (req: Request, res: Response) => {
  try {
    const { did } = req.query;

    if (!did || typeof did !== 'string') {
      return res.status(400).json({
        error: 'InvalidRequest',
        message: 'Missing did parameter'
      });
    }

    const result = await pool.query(
      `SELECT o.operation, o.created_at
       FROM operation o
       WHERE o.repo = $1
       ORDER BY o.created_at DESC
       LIMIT 1`,
      [did]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'NotFound',
        message: 'DID not found'
      });
    }

    res.json({
      did,
      operation: result.rows[0].operation,
      indexedAt: result.rows[0].created_at
    });
  } catch (error: any) {
    console.error('Error getting account:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  }
});

app.get('/xrpc/plc.getOperationLog', async (req: Request, res: Response) => {
  try {
    const { did } = req.query;

    if (!did || typeof did !== 'string') {
      return res.status(400).json({
        error: 'InvalidRequest',
        message: 'Missing did parameter'
      });
    }

    const result = await pool.query(
      `SELECT o.operation, o.created_at, o.prev, o.sig
       FROM operation o
       WHERE o.repo = $1
       ORDER BY o.created_at ASC`,
      [did]
    );

    res.json({
      did,
      operations: result.rows.map(row => ({
        operation: row.operation,
        createdAt: row.created_at,
        prev: row.prev?.toString('hex'),
        sig: row.sig?.toString('hex')
      }))
    });
  } catch (error: any) {
    console.error('Error getting operation log:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  }
});

app.get('/xrpc/com.atproto.identity.resolveDid', async (req: Request, res: Response) => {
  try {
    const { did } = req.query;

    if (!did || typeof did !== 'string') {
      return res.status(400).json({
        error: 'InvalidRequest',
        message: 'Missing did parameter'
      });
    }

    const result = await pool.query(
      `SELECT o.operation
       FROM operation o
       WHERE o.repo = $1
       ORDER BY o.created_at DESC
       LIMIT 1`,
      [did]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'NotFound',
        message: 'DID not found'
      });
    }

    const op = result.rows[0].operation;
    const doc = {
      "@context": ["https://www.w3.org/ns/did/v1"],
      id: did,
      verificationMethod: [{
        id: `${did}#signingKey`,
        type: "Multikey",
        controller: did,
        publicKeyMultibase: op.signingKey
      }],
      rotationKeys: op.rotationKeys?.map((k: string) => `${did}#${k}`) || [],
      alsoKnownAs: op.handle ? [`at://${op.handle}`] : [],
      service: Object.entries(op.services || {}).map(([id, svc]: [string, any]) => ({
        id,
        type: svc.type,
        serviceEndpoint: svc.endpoint
      }))
    };

    res.json(doc);
  } catch (error: any) {
    console.error('Error resolving DID:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  }
});

async function startServer() {
  await initializeDatabase();
  
  app.listen(parseInt(PORT), '0.0.0.0', () => {
    console.log(`PLC Directory test server running on port ${PORT}`);
  });
}

startServer().catch(console.error);
