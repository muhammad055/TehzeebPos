const { app, BrowserWindow, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const http = require('http');
const { spawn } = require('child_process');

const BACKEND_URL = 'http://localhost:5050';
const HEALTH_URL = `${BACKEND_URL}/api/settings`;

// Known location of the pre-existing dev database on this machine — the app
// has real menu/settings/order data there already, so a first-time run of
// the packaged app migrates it in instead of starting blank. Harmless no-op
// if this path doesn't exist (e.g. installed on a different PC later).
const LEGACY_DB_CANDIDATES = ['D:\\TehzeebPOS\\backend\\app.db'];

let backendProcess = null;
let mainWindow = null;

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

function backendPaths() {
  // Immutable code (exe + dlls + shipped wwwroot template) — read-only once
  // installed (typically under Program Files).
  const codeDir = app.isPackaged
    ? path.join(process.resourcesPath, 'backend')
    : path.join(__dirname, 'resources', 'backend');
  // Writable per-user data dir (SQLite DB + uploaded images) — must not live
  // under Program Files, which standard user accounts can't write to.
  const dataDir = path.join(app.getPath('userData'), 'backend-data');
  return { codeDir, exe: path.join(codeDir, 'PosApi.exe'), dataDir };
}

function ensureDataDir(codeDir, dataDir) {
  if (fs.existsSync(dataDir)) return; // already initialized on a previous run

  fs.mkdirSync(dataDir, { recursive: true });

  const shippedWwwroot = path.join(codeDir, 'wwwroot');
  if (fs.existsSync(shippedWwwroot)) {
    fs.cpSync(shippedWwwroot, path.join(dataDir, 'wwwroot'), { recursive: true });
  }

  const legacyDb = LEGACY_DB_CANDIDATES.find((p) => fs.existsSync(p));
  if (legacyDb) {
    fs.copyFileSync(legacyDb, path.join(dataDir, 'app.db'));
  }
}

function startBackend() {
  const { codeDir, exe, dataDir } = backendPaths();
  if (!fs.existsSync(exe)) {
    dialog.showErrorBox(
      'Tehzeeb POS',
      `Backend not found at:\n${exe}\n\nRun "npm run prepare-resources" before packaging/starting the app.`
    );
    app.quit();
    return;
  }

  ensureDataDir(codeDir, dataDir);

  backendProcess = spawn(exe, ['--urls', BACKEND_URL], {
    cwd: dataDir,
    windowsHide: true,
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
  startBackend();

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

  try {
    await waitForBackend();
    await mainWindow.loadURL(BACKEND_URL);
  } catch (err) {
    dialog.showErrorBox('Tehzeeb POS', `Could not reach the backend:\n${err.message}`);
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

app.on('before-quit', stopBackend);
app.on('will-quit', stopBackend);
