// Prepares everything electron-builder needs: builds the Angular frontend,
// publishes the backend as a self-contained win-x64 exe, merges the Angular
// build into the published wwwroot, and generates the app icon.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const desktopDir = path.join(__dirname, '..');
const frontendDir = path.join(root, 'frontend-ng');
const backendCsproj = path.join(root, 'backend', 'PosApi.csproj');
const publishDir = path.join(desktopDir, 'resources', 'backend');
const angularBrowserDir = path.join(frontendDir, 'dist', 'tehzeeb-pos', 'browser');
const logoSource = path.join(root, 'backend', 'wwwroot', 'TL.png');
const iconOut = path.join(desktopDir, 'build', 'icon.ico');

function run(cmd, cwd) {
  console.log(`\n$ ${cmd}  (in ${cwd})`);
  execSync(cmd, { cwd, stdio: 'inherit', shell: true });
}

console.log('== 1/4: Building Angular frontend ==');
run('npm run build', frontendDir);

console.log('== 2/4: Publishing backend (self-contained win-x64) ==');
fs.rmSync(publishDir, { recursive: true, force: true });
run(
  `dotnet publish "${backendCsproj}" -c Release -r win-x64 --self-contained true ` +
    `-p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "${publishDir}"`,
  root
);

console.log('== 3/4: Copying Angular build into published wwwroot ==');
if (!fs.existsSync(angularBrowserDir)) {
  throw new Error(`Angular build output not found at ${angularBrowserDir}`);
}
const wwwrootDir = path.join(publishDir, 'wwwroot');
fs.mkdirSync(wwwrootDir, { recursive: true });
fs.cpSync(angularBrowserDir, wwwrootDir, { recursive: true, force: true });

console.log('== 4/4: Generating app icon from TL.png ==');
fs.mkdirSync(path.dirname(iconOut), { recursive: true });
const sharp = require('sharp');
const pngToIco = require('png-to-ico');
// TL.png (74x67) isn't square, and png-to-ico requires a square source —
// pad it onto a transparent square canvas rather than cropping/stretching.
sharp(logoSource)
  .resize(256, 256, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
  .png()
  .toBuffer()
  .then((squarePng) => pngToIco(squarePng))
  .then((icoBuf) => {
    fs.writeFileSync(iconOut, icoBuf);
    console.log(`Icon written to ${iconOut}`);
    console.log('\nDone. Run "electron-builder" (or "npm run dist") next.');
  })
  .catch((err) => {
    console.error('Failed to generate icon:', err);
    process.exit(1);
  });
