const { app, BrowserWindow, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');

const BACKEND_URL = 'http://localhost:5050';
const HEALTH_URL = `${BACKEND_URL}/api/settings`;

// The backend is Postgres-only (see backend/CLAUDE.md "Multi-tenancy & auth").
// Desktop bundles its own local, portable Postgres (via the `embedded-postgres`
// npm package — real Postgres binaries, no separate install/admin rights
// needed) rather than requiring the restaurant to have a database server, and
// rather than resurrecting SQLite support in the backend. Runs on a
// non-default port so it can never collide with a real Postgres install.
const PG_PORT = 55432;
const PG_USER = 'postgres';
const PG_PASSWORD = 'postgres'; // local-only, loopback-bound, per-install isolated data dir — see CLAUDE.md
const PG_DATABASE = 'tehzeeb_pos';

let backendProcess = null;
let pg = null;
let mainWindow = null;
let isQuitting = false;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(startApp);
}

function appPaths() {
  // Immutable code (exe + dlls + shipped wwwroot template) — read-only once
  // installed (typically under Program Files).
  const codeDir = app.isPackaged
    ? path.join(process.resourcesPath, 'backend')
    : path.join(__dirname, 'resources', 'backend');
  // Writable per-user data — must not live under Program Files, which
  // standard user accounts can't write to.
  const userData = app.getPath('userData');
  return {
    codeDir,
    exe: path.join(codeDir, 'PosApi.exe'),
    backendDataDir: path.join(userData, 'backend-data'),
    pgDataDir: path.join(userData, 'pgdata'),
    secretsFile: path.join(userData, 'secrets.json'),
  };
}

function ensureBackendDataDir(codeDir, dataDir) {
  if (fs.existsSync(dataDir)) return; // already initialized on a previous run

  fs.mkdirSync(dataDir, { recursive: true });

  const shippedWwwroot = path.join(codeDir, 'wwwroot');
  if (fs.existsSync(shippedWwwroot)) {
    fs.cpSync(shippedWwwroot, path.join(dataDir, 'wwwroot'), { recursive: true });
  }
}

// The backend needs a stable JWT signing secret across restarts (otherwise
// every relaunch would invalidate all logged-in sessions) — generated once
// per install and persisted alongside the other per-user app data.
function loadOrCreateJwtSecret(secretsFile) {
  if (fs.existsSync(secretsFile)) {
    return JSON.parse(fs.readFileSync(secretsFile, 'utf8')).jwtSecret;
  }
  const jwtSecret = crypto.randomBytes(48).toString('hex');
  fs.mkdirSync(path.dirname(secretsFile), { recursive: true });
  fs.writeFileSync(secretsFile, JSON.stringify({ jwtSecret }), { mode: 0o600 });
  return jwtSecret;
}

async function startPostgres(pgDataDir) {
  // embedded-postgres is ESM-only; main.js stays CommonJS, so this is a
  // dynamic import rather than a top-level require().
  const { default: EmbeddedPostgres } = await import('embedded-postgres');

  // initdb refuses to run against a non-empty directory, so only call
  // .initialise()/.createDatabase() the very first time — PG_VERSION is the
  // marker file initdb itself creates once a cluster exists.
  const isFirstRun = !fs.existsSync(path.join(pgDataDir, 'PG_VERSION'));

  pg = new EmbeddedPostgres({
    databaseDir: pgDataDir,
    port: PG_PORT,
    user: PG_USER,
    password: PG_PASSWORD,
    persistent: true,
    onLog: () => {}, // Postgres's own log stream is noisy and not actionable for the end user
    onError: (err) => console.error('[postgres]', err),
  });

  if (isFirstRun) {
    await pg.initialise();
  }
  await pg.start();
  if (isFirstRun) {
    await pg.createDatabase(PG_DATABASE);
  }
}

async function stopPostgres() {
  if (!pg) return;
  try {
    await pg.stop();
  } catch {
    // ignore — best effort during shutdown
  }
  pg = null;
}

function startBackend(exe, dataDir, jwtSecret) {
  backendProcess = spawn(exe, ['--urls', BACKEND_URL], {
    cwd: dataDir,
    windowsHide: true,
    env: {
      ...process.env,
      ASPNETCORE_ENVIRONMENT: 'Production',
      ConnectionStrings__Default: `Host=127.0.0.1;Port=${PG_PORT};Database=${PG_DATABASE};Username=${PG_USER};Password=${PG_PASSWORD}`,
      Jwt__Secret: jwtSecret,
      // Printing:Mode intentionally left unset — desktop always prints
      // in-process (backend and printer are the same machine). See
      // backend/PrintDispatch.cs.
    },
  });

  backendProcess.on('error', (err) => {
    dialog.showErrorBox('Tehzeeb POS', `Failed to start backend:\n${err.message}`);
  });

  backendProcess.on('exit', (code) => {
    backendProcess = null;
    // If the backend dies unexpectedly while the app is still open, let the
    // user know instead of leaving a blank/broken window.
    if (mainWindow && !mainWindow.isDestroyed() && code !== 0 && code !== null) {
      dialog.showErrorBox('Tehzeeb POS', `Backend stopped unexpectedly (exit code ${code}).`);
    }
  });
}

function waitForBackend(timeoutMs = 30000, intervalMs = 400) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const attempt = () => {
      // Any HTTP response (even a 401 from an authenticated-only endpoint)
      // proves the server is up and listening — that's all this checks for.
      const req = http.get(HEALTH_URL, (res) => {
        res.resume();
        resolve();
      });
      req.on('error', () => {
        if (Date.now() > deadline) reject(new Error('Backend did not respond in time.'));
        else setTimeout(attempt, intervalMs);
      });
      req.setTimeout(intervalMs, () => req.destroy());
    };
    attempt();
  });
}

async function startApp() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    show: false,
    icon: path.join(__dirname, 'build', 'icon.ico'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadURL(
    'data:text/html,' +
      encodeURIComponent(
        '<body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif;background:#130330;color:#f5c518"><p>Starting Tehzeeb POS…</p></body>'
      )
  );
  mainWindow.show();

  const { codeDir, exe, backendDataDir, pgDataDir, secretsFile } = appPaths();

  try {
    if (!fs.existsSync(exe)) {
      throw new Error(`Backend not found at:\n${exe}\n\nRun "npm run prepare-resources" before packaging/starting the app.`);
    }

    await startPostgres(pgDataDir);

    const jwtSecret = loadOrCreateJwtSecret(secretsFile);
    ensureBackendDataDir(codeDir, backendDataDir);
    startBackend(exe, backendDataDir, jwtSecret);

    await waitForBackend();
    await mainWindow.loadURL(BACKEND_URL);
  } catch (err) {
    dialog.showErrorBox('Tehzeeb POS', `Could not start:\n${err.message}`);
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  app.on('window-all-closed', () => {
    app.quit();
  });
}

function stopBackend() {
  if (backendProcess) {
    try {
      backendProcess.kill();
    } catch {
      // ignore — process may already be gone
    }
    backendProcess = null;
  }
}

// Postgres must be stopped cleanly (not just abandoned) to avoid corrupting
// the data directory, so quitting is deferred until both processes are down.
app.on('before-quit', (e) => {
  if (isQuitting) return;
  isQuitting = true;
  e.preventDefault();
  stopBackend();
  stopPostgres().finally(() => app.exit(0));
});
