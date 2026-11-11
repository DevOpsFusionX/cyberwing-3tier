// ============================================================
//  Cyberwing.pk Guestbook - Backend (Application tier)
//  Node.js + Express + MySQL + Prometheus metrics
// ============================================================

const express = require('express');          // web server / API library
const mysql = require('mysql2/promise');     // MySQL driver (async style)
const client = require('prom-client');       // Prometheus metrics library

const app = express();
const PORT = process.env.PORT || 3000;

// nginx reverse proxy ke peechay chal rahe hain, is liye trust proxy ON
app.set('trust proxy', true);

app.use(express.json({ limit: '100kb' }));   // JSON body parhne ke liye

// ---------- Prometheus metrics ----------
client.collectDefaultMetrics();              // CPU / memory / event loop etc.

const httpCounter = new client.Counter({
  name: 'http_requests_total',               // metric ka naam
  help: 'Kitni HTTP requests aayi',
  labelNames: ['method', 'route', 'status'], // har request par 3 labels
});

app.use((req, res, next) => {
  res.on('finish', () => {                   // jawab mukammal hone par
    httpCounter.inc({
      method: req.method,
      route: req.route ? req.route.path : 'other',
      status: res.statusCode,
    });
  });
  next();
});

// ---------- Database connection pool ----------
const pool = mysql.createPool({
  host: process.env.DB_HOST,                 // database ka address (service name)
  user: process.env.DB_USER,                 // DB user
  password: process.env.DB_PASSWORD,         // DB password (code mein kabhi nahi!)
  database: process.env.DB_NAME,             // DB ka naam
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// ---------- Routes ----------

// 1) Health: backend + database dono zinda hain?
app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'up' });
  } catch (e) {
    res.status(503).json({ status: 'degraded', db: 'down' });
  }
});

// 2) Messages ki list (naye pehle, max 20)
app.get('/api/messages', async (req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, name, message, created_at FROM messages ORDER BY id DESC LIMIT 20'
    );
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'database error' });
  }
});

// 3) Naya message save karo
app.post('/api/messages', async (req, res) => {
  const { name, message } = req.body;
  if (!name || !message) {
    return res.status(400).json({ error: 'name aur message zaroori hain' });
  }
  try {
    await pool.query(
      'INSERT INTO messages (name, message) VALUES (?, ?)',
      [String(name).slice(0, 50), String(message).slice(0, 255)]  // ? = SQL injection se hifazat
    );
    res.status(201).json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'database error' });
  }
});

// 4) Prometheus yahan se metrics uthata hai (sirf internal network se)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

// ---------- Server start ----------
const server = app.listen(PORT, () => {
  console.log(`Backend port ${PORT} par chal raha hai`);
});

// ---------- Graceful shutdown (docker stop par saaf band hona) ----------
function shutdown(signal) {
  console.log(`${signal} mila: server band kiya ja raha hai...`);
  server.close(async () => {
    try { await pool.end(); } catch (_) {}
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref(); // 10s baad zor se band
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
