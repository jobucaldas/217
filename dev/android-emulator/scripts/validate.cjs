const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require(path.join(process.env.ANDROID_REPO_ROOT, 'e2e/node_modules/playwright'));

const ROOT = process.env.ANDROID_REPO_ROOT;
const ARTIFACT_DIR = process.env.ANDROID_ARTIFACT_DIR || path.join(ROOT, 'artifacts/android');
const DEVICE_ORIGIN = process.env.ANDROID_ORIGIN || `http://localhost:${process.env.ANDROID_HOST_PORT || '8080'}`;
const HOST_ORIGIN = process.env.ANDROID_HOST_ORIGIN || `http://localhost:${process.env.ANDROID_HOST_SERVICE_PORT || '18080'}`;
const ORIGIN = DEVICE_ORIGIN;
const CDP_PORT = Number(process.env.ANDROID_CDP_PORT || '9222');
const DB_URL = process.env.ANDROID_DATABASE_URL || 'postgres://app_217:app_217@localhost:5432/app_217?sslmode=disable';
const CHROME_PACKAGE = process.env.ANDROID_CHROME_PACKAGE || 'com.android.chrome';

function log(message) {
  console.log(`[android-validate] ${message}`);
}

function adb(args, options = {}) {
  return execFileSync('adb', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options }).trim();
}

function adbBuffer(args, options = {}) {
  return execFileSync('adb', args, { stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 20 * 1024 * 1024, ...options });
}

function psql(sql) {
  return execFileSync('psql', [DB_URL, '-Atc', sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(predicate, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const value = await predicate();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await sleep(2000);
  }
  throw new Error(`timed out waiting for ${label}${lastError ? `: ${lastError.message || lastError}` : ''}`);
}

function chromeVersion() {
  const output = adb(['shell', 'dumpsys', 'package', CHROME_PACKAGE]);
  const match = output.match(/versionName=([^\s]+)/);
  return match ? match[1] : '';
}

function emulatorInfo() {
  const api = adb(['shell', 'getprop', 'ro.build.version.sdk']);
  const release = adb(['shell', 'getprop', 'ro.build.version.release']);
  const product = adb(['shell', 'getprop', 'ro.product.model']);
  const avd = adb(['shell', 'getprop', 'ro.boot.qemu.avd_name']);
  const abi = adb(['shell', 'getprop', 'ro.product.cpu.abi']);
  return { api: api.trim(), release: release.trim(), product: product.trim(), avd: avd.trim(), abi: abi.trim() };
}

function adbLines(args, options = {}) {
  return adb(args, options).split(/\r?\n/).filter(Boolean);
}

function unixSocketNames() {
  return adbLines(['shell', 'cat', '/proc/net/unix']).filter((line) => /chrome_devtools_remote|webview_devtools_remote/.test(line)).map((line) => {
    const parts = line.trim().split(/\s+/);
    return parts[parts.length - 1] || line.trim();
  });
}

function chromePid() {
  try {
    return adb(['shell', 'pidof', 'com.android.chrome']);
  } catch (_) {
    return '';
  }
}

function recordChromeSocketCheckpoint(reason) {
  const sockets = unixSocketNames();
  const pid = chromePid();
  const version = chromeVersion();
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'chrome-socket-checkpoint.json'), JSON.stringify({ reason, pid, version, sockets }, null, 2));
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'adb-forward-list.txt'), adb(['forward', '--list']));
  if (!sockets.length) {
    adb(['shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml']);
    fs.writeFileSync(path.join(ARTIFACT_DIR, 'chrome-uiautomator.xml'), adb(['exec-out', 'cat', '/sdcard/window_dump.xml']));
    fs.writeFileSync(path.join(ARTIFACT_DIR, 'chrome-socket-screenshot.png'), adbBuffer(['exec-out', 'screencap', '-p']));
  }
}

function forwardChromeSocket() {
  const sockets = unixSocketNames();
  const target = sockets.find((socket) => socket.includes('chrome_devtools_remote')) || sockets.find((socket) => socket.includes('webview_devtools_remote'));
  if (!target) return false;
  const socketName = target.replace(/^@/, '');
  try {
    adb(['forward', '--remove', `tcp:${CDP_PORT}`]);
  } catch (_) {}
  adb(['forward', `tcp:${CDP_PORT}`, `localabstract:${socketName}`]);
  return true;
}

async function connectBrowser() {
  const cdpUrl = `http://127.0.0.1:${CDP_PORT}`;
  await waitFor(async () => {
    try {
      return await fetch(`${cdpUrl}/json/version`).then((r) => r.ok);
    } catch (_) {
      return false;
    }
  }, 120000, 'Chrome DevTools endpoint');
  return chromium.connectOverCDP(cdpUrl);
}

async function pageStatus(page) {
  return page.evaluate(async () => {
    const status = JSON.parse(await window.pwa217.status());
    return {
      secureContext: window.isSecureContext,
      hasServiceWorker: 'serviceWorker' in navigator,
      hasPushManager: 'PushManager' in window,
      hasNotification: 'Notification' in window,
      notificationPermission: Notification.permission,
      pwaStatus: status,
      browserTimezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      locationHref: location.href,
      localDate: window.pwa217.localDate(),
    };
  });
}

function futureTime(minutesAhead) {
  const now = new Date();
  const target = new Date(now.getTime() + minutesAhead * 60 * 1000);
  return `${String(target.getHours()).padStart(2, '0')}:${String(target.getMinutes()).padStart(2, '0')}`;
}

function localDateFromPage(page) {
  return page.evaluate(() => window.pwa217.localDate());
}

function captureScreen(filename) {
  const file = path.join(ARTIFACT_DIR, filename);
  fs.writeFileSync(file, adbBuffer(['exec-out', 'screencap', '-p']));
  return file;
}

const EXPECTED_NOTIFICATION_BODY = 'Hora de registrar seu anticoncepcional • Time to record your medication';

function matchingNotificationRecord(dump, tag) {
  return dump.split(/(?=\s*NotificationRecord\()/).find((block) => block.includes('pkg=com.android.chrome') && block.includes(tag) && block.includes('android.title=String (217)') && block.includes(`android.text=String (${EXPECTED_NOTIFICATION_BODY})`)) || null;
}

function dumpsysNotification(tag, filename) {
  const output = adb(['shell', 'dumpsys', 'notification', '--noredact']);
  const needle = String(tag);
  const lines = output.split(/\r?\n/);
  const matchIndexes = [];
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index].includes(needle)) {
      matchIndexes.push(index);
    }
  }
  const start = matchIndexes.length ? Math.max(0, matchIndexes[0] - 20) : 0;
  const end = matchIndexes.length ? Math.min(lines.length, matchIndexes[matchIndexes.length - 1] + 20) : Math.min(lines.length, 120);
  const slice = lines.slice(start, end).join('\n');
  fs.writeFileSync(path.join(ARTIFACT_DIR, filename), slice);
  return slice;
}

function parseBounds(xml, searchTexts) {
  const nodes = [...xml.matchAll(/<node\b[^>]*>/g)].map((match) => match[0]);
  for (const node of nodes) {
    const textMatch = node.match(/text="([^"]*)"/);
    const descMatch = node.match(/content-desc="([^"]*)"/);
    const boundsMatch = node.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
    if (!boundsMatch) continue;
    const text = `${textMatch ? textMatch[1] : ''} ${descMatch ? descMatch[1] : ''}`.toLowerCase();
    if (searchTexts.some((needle) => text.includes(needle.toLowerCase()))) {
      const [, x1, y1, x2, y2] = boundsMatch;
      return {
        x1: Number(x1),
        y1: Number(y1),
        x2: Number(x2),
        y2: Number(y2),
        centerX: Math.floor((Number(x1) + Number(x2)) / 2),
        centerY: Math.floor((Number(y1) + Number(y2)) / 2),
        matchedText: text,
      };
    }
  }
  return null;
}

function tapFallback() {
  const wmSize = adb(['shell', 'wm', 'size']);
  const sizeMatch = wmSize.match(/Physical size:\s*(\d+)x(\d+)/i);
  if (!sizeMatch) return { x: 540, y: 240 };
  const width = Number(sizeMatch[1]);
  return { x: Math.floor(width / 2), y: 240 };
}

function captureUiDump() {
  try { adb(['shell', 'rm', '-f', '/sdcard/window_dump.xml']); } catch (_) {}
  try { adb(['shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml']); } catch (_) {}
  let remote = '';
  try { remote = adb(['exec-out', 'cat', '/sdcard/window_dump.xml']); } catch (_) { return null; }
  if (!remote.includes('<hierarchy') || !remote.includes('<node')) return null;
  return remote;
}

function recordUiCheckpoint(prefix, xml, screenshot = true) {
  fs.writeFileSync(path.join(ARTIFACT_DIR, `${prefix}.xml`), xml);
  if (screenshot) fs.writeFileSync(path.join(ARTIFACT_DIR, `${prefix}.png`), adbBuffer(['exec-out', 'screencap', '-p']));
}

function recordOsNotificationPermission() {
  const permission = adb(['shell', 'dumpsys', 'package', CHROME_PACKAGE]);
  const appops = adb(['shell', 'cmd', 'appops', 'get', CHROME_PACKAGE, 'POST_NOTIFICATION']);
  const granted = /android.permission.POST_NOTIFICATIONS: granted=true/.test(permission);
  const allowed = /POST_NOTIFICATION.*allow/i.test(appops);
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'os-notification-permission.json'), JSON.stringify({ granted, allowed, appopsMode: allowed ? 'allow' : 'other' }, null, 2));
  if (!granted || !allowed) throw new Error('Chrome OS notification permission/appop not allowed');
}

async function handleNotificationPermission(page) {
  const permission = await page.evaluate(() => Notification.permission);
  if (permission === 'granted') return;
  const before = await waitFor(async () => {
    const xml = captureUiDump();
    return xml && /Allow|Block/i.test(xml) && /notification|Chrome|localhost/i.test(xml) ? xml : null;
  }, 90000, 'Chrome notification permission dialog');
  recordUiCheckpoint('notification-permission-before', before);
  const allow = parseBounds(before, ['Allow']);
  if (!allow) throw new Error('notification permission dialog did not expose Allow');
  adb(['shell', 'input', 'tap', String(allow.centerX), String(allow.centerY)]);
  await waitFor(() => page.evaluate(() => Notification.permission === 'granted'), 30000, 'notification permission grant');
  recordUiCheckpoint('notification-permission-after', captureUiDump() || '<hierarchy />');
}

function hasAnrDialog(xml) {
  return /Pixel Launcher isn't responding|close app|wait/i.test(xml);
}

function tapAnrWait(xml) {
  const waitNode = parseBounds(xml, ['Wait']);
  if (!waitNode) return null;
  adb(['shell', 'input', 'tap', String(waitNode.centerX), String(waitNode.centerY)]);
  return waitNode;
}

async function handleLauncherAnr() {
  let before;
  try {
    before = await waitFor(async () => {
      const xml = captureUiDump();
      return xml && hasAnrDialog(xml) ? xml : null;
    }, 90000, 'launcher ANR dialog');
  } catch (error) {
    // On some cold boots uiautomator is unavailable while the system dialog is visible.
    // Use its stable Pixel 7 portrait coordinates as a bounded fallback.
    const wmSize = adb(['shell', 'wm', 'size']);
    if (!/1080x2400/.test(wmSize)) throw error;
    adb(['shell', 'input', 'tap', '540', '1327']);
    await settleChrome();
    before = captureUiDump() || '<hierarchy><node text="Pixel Launcher isn\'t responding" /></hierarchy>';
  }
  recordUiCheckpoint('launcher-anr-before', before);
  const tapped = tapAnrWait(before) || { centerX: 540, centerY: 1327 };
  if (!tapped) throw new Error('launcher ANR Wait button not found');
  await settleChrome();
  const after = await waitFor(async () => {
    const xml = captureUiDump();
    return xml && !hasAnrDialog(xml) ? xml : null;
  }, 30000, 'launcher ANR dismissal');
  recordUiCheckpoint('launcher-anr-after', after);
  return { tapped };
}

function writeFallbackJson(data) {
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'chrome-first-run-fallback.json'), JSON.stringify(data, null, 2));
}

function tapNodeByTexts(xml, texts) {
  const bounds = parseBounds(xml, texts);
  if (!bounds) return null;
  adb(['shell', 'input', 'tap', String(bounds.centerX), String(bounds.centerY)]);
  return bounds;
}

async function settleChrome() {
  await sleep(5000);
}

async function handleChromeFirstRun() {
  const prior = { resourceId: 'com.android.chrome:id/signin_fre_dismiss_button', bounds: { x1: 63, y1: 2030, x2: 1017, y2: 2156 }, display: { width: 1080, height: 2400 } };
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const before = await waitFor(async () => captureUiDump(), 60000, `Chrome first-run UI attempt ${attempt}`);
    recordUiCheckpoint(`chrome-first-run-before-${attempt}`, before);
    const button = parseBounds(before, ['Use without an account']);
    if (button) {
      adb(['shell', 'input', 'tap', String(button.centerX), String(button.centerY)]);
      await settleChrome();
    } else {
      const wmSize = adb(['shell', 'wm', 'size']);
      const sizeMatch = wmSize.match(/Physical size:\s*(\d+)x(\d+)/i);
      const width = sizeMatch ? Number(sizeMatch[1]) : 0;
      const height = sizeMatch ? Number(sizeMatch[2]) : 0;
      if (width === prior.display.width && height === prior.display.height) {
        const x = Math.round(width * 0.5);
        const y = Math.round(height * 0.872);
        writeFallbackJson({ attempt, prior, wmSize: wmSize.trim(), computed: { x, y } });
        adb(['shell', 'input', 'tap', String(x), String(y)]);
        await settleChrome();
      } else {
        writeFallbackJson({ attempt, prior, wmSize: wmSize.trim(), skipped: 'resolution mismatch' });
      }
    }
    const after = await waitFor(async () => captureUiDump(), 60000, `Chrome first-run follow-up UI attempt ${attempt}`);
    recordUiCheckpoint(`chrome-first-run-after-${attempt}`, after);
    const followUp = parseBounds(after, ['Continue', 'Accept & continue']);
    if (followUp) {
      adb(['shell', 'input', 'tap', String(followUp.centerX), String(followUp.centerY)]);
      await settleChrome();
      return { attempt, tapped: button || prior.bounds, followUp };
    }
    if (parseBounds(after, ['Use without an account'])) return { attempt, tapped: button || prior.bounds, followUp: null };
  }
  return null;
}

async function main() {
  fs.mkdirSync(ARTIFACT_DIR, { recursive: true });
  for (const file of ['launcher-anr-before.xml', 'launcher-anr-after.xml', 'chrome-first-run-before.xml', 'chrome-first-run-after.xml']) {
    try { fs.unlinkSync(path.join(ARTIFACT_DIR, file)); } catch (_) {}
  }
  for (const file of ['chrome-first-run-before.xml', 'chrome-first-run-after.xml']) {
    try { fs.unlinkSync(path.join(ARTIFACT_DIR, file)); } catch (_) {}
  }

  log('handling launcher ANR');
  await handleLauncherAnr();
  log('handling Chrome first run');
  await handleChromeFirstRun();
  async function recoverChromeForeground(attempt) {
    let commandLineCheck = '';
    try { commandLineCheck = adb(['shell', 'cat', '/data/local/tmp/chrome-command-line']); } catch (_) {}
    if (!commandLineCheck.includes('--remote-debugging-port=')) {
      const commandLine = `chrome --no-first-run --no-default-browser-check --disable-fre --disable-background-networking --disable-sync --disable-component-update --remote-debugging-port=${CDP_PORT}`;
      adb(['shell', `echo '${commandLine}' > /data/local/tmp/chrome-command-line && chmod 644 /data/local/tmp/chrome-command-line`]);
      commandLineCheck = adb(['shell', 'cat', '/data/local/tmp/chrome-command-line']);
    }
    commandLineCheck = commandLineCheck.replace(/[^a-zA-Z0-9_ .:=/-]/g, '');
    fs.writeFileSync(path.join(ARTIFACT_DIR, `chrome-command-line-${attempt}.json`), JSON.stringify({ attempt, commandLine: commandLineCheck }, null, 2));
    if (!commandLineCheck.includes('--remote-debugging-port=')) throw new Error('Chrome command line missing remote debugging flag');
    let launchOutput = '';
    try { adb(['shell', 'monkey', '-p', CHROME_PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1']); launchOutput = adb(['shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW', '-d', ORIGIN, '-p', CHROME_PACKAGE]); } catch (error) { launchOutput = String(error); }
    const foreground = adb(['shell', 'dumpsys', 'window', 'windows']).match(/mCurrentFocus=.*?([^/ ]+\/${CHROME_PACKAGE}[^ ]*)/);
    fs.writeFileSync(path.join(ARTIFACT_DIR, `chrome-relaunch-${attempt}.json`), JSON.stringify({ attempt, launchOutput: launchOutput.slice(0, 1000), foreground: foreground ? foreground[1] : '' }, null, 2));
    await waitFor(() => /(?:mResumedActivity|topResumedActivity).*com\.android\.chrome/.test(adb(['shell', 'dumpsys', 'activity', 'activities'])), 30000, 'Chrome foreground');
  }
  log('recovering Chrome foreground');
  try {
    await recoverChromeForeground(1);
  } catch (error) {
    await recoverChromeForeground(2);
  }
  log('connecting to Chrome over CDP');
  try {
    await waitFor(async () => forwardChromeSocket(), 120000, 'Chrome devtools socket');
  } catch (error) {
    recordChromeSocketCheckpoint(`no-devtools-socket: ${error.message || error}`);
    throw error;
  }
  const browser = await connectBrowser();
  const context = browser.contexts()[0] || await browser.newContext();
  try {
    await context.grantPermissions(['notifications'], { origin: ORIGIN });
  } catch (_) {
    // CDP contexts may not expose grantPermissions reliably; the appops grant still helps.
  }

  let page = context.pages().find((candidate) => candidate.url().startsWith(ORIGIN)) || context.pages()[0];
  if (!page) page = await context.newPage();
  await page.goto(ORIGIN, { waitUntil: 'networkidle' });

  const envBefore = await pageStatus(page);
  const accountSuffix = Date.now().toString(36);
  const account = {
    email: `android-${accountSuffix}@example.com`,
    name: `Android ${accountSuffix}`,
    password: `Passw0rd-${accountSuffix}!`,
  };

  log('registering a fresh account');
  await page.getByRole('button', { name: /Novo\?|New user/i }).click();
  await page.locator('#auth-email').fill(account.email);
  await page.locator('#auth-name').fill(account.name);
  await page.locator('#auth-password').fill(account.password);
  const registerResponsePromise = page.waitForResponse((response) => response.url().includes('/api/auth/register') && response.request().method() === 'POST', { timeout: 30000 });
  await page.getByRole('button', { name: /Cadastrar|Register/i }).click();
  const registerResponse = await registerResponsePromise;
  const registerBody = await registerResponse.json();
  const apiKey = registerBody.api_key;
  if (!apiKey) throw new Error('register response missing api_key');

  log('opening reminder settings');
  await page.getByRole('button', { name: /Opções|Options/i }).click();
  await page.locator('#reminder-time').waitFor({ state: 'visible', timeout: 30000 });
  const browserClock = await page.evaluate(() => {
    const now = new Date();
    return {
      hour: now.getHours(),
      minute: now.getMinutes(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      localDate: window.pwa217.localDate(),
    };
  });
  const reminderTime = futureTime(2);
  await page.locator('#reminder-time').fill(reminderTime);
  const reminderResponses = [];
  const responseLogger = (response) => {
    if (response.url().includes('/api/reminders/')) reminderResponses.push({ url: response.url(), status: response.status(), method: response.request().method() });
  };
  page.on('response', responseLogger);
  await page.getByRole('button', { name: /Ativar lembrete neste dispositivo|Enable reminder on this device/i }).click();
  await handleNotificationPermission(page);
  recordOsNotificationPermission();
  const statusAfterEnable = await waitFor(async () => {
    const status = await pageStatus(page);
    const response = await fetch(`${HOST_ORIGIN}/api/reminders/preferences`, { headers: { 'X-API-Key': apiKey } });
    const body = await response.text();
    if (!response.ok || !response.headers.get('content-type')?.includes('application/json')) throw new Error(`preferences HTTP ${response.status}: ${body.slice(0, 160)}`);
    const preference = JSON.parse(body);
    return status.pwaStatus.subscribed && preference.enabled && preference.deliverable ? status : null;
  }, 90000, 'subscribed deliverable reminder');
  page.off('response', responseLogger);
  const preferenceResponse = await fetch(`${HOST_ORIGIN}/api/reminders/preferences`, { headers: { 'X-API-Key': apiKey } });
  const preferenceBody = await preferenceResponse.text();
  if (!preferenceResponse.ok || !preferenceResponse.headers.get('content-type')?.includes('application/json')) throw new Error(`preferences HTTP ${preferenceResponse.status}: ${preferenceBody.slice(0, 160)}`);
  const preferenceAfterEnable = JSON.parse(preferenceBody);
  if (!statusAfterEnable.pwaStatus.subscribed || !statusAfterEnable.pwaStatus.secure) {
    throw new Error(`unexpected browser status: ${JSON.stringify(statusAfterEnable)}`);
  }
  if (!preferenceAfterEnable.deliverable || !preferenceAfterEnable.enabled) {
    throw new Error(`reminder preference not deliverable: ${JSON.stringify(preferenceAfterEnable)}`);
  }

  const reminderDate = browserClock.localDate;
  const notificationTag = `217-reminder-${reminderDate}`;
  const beforeCloseScreen = captureScreen('01-reminder-enabled-before-close.png');
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'pre-close-state.json'), JSON.stringify({
    emulator: emulatorInfo(),
    chromeVersion: chromeVersion(),
    browserClock,
    envBefore,
    statusAfterEnable,
    preferenceAfterEnable,
    reminderTime,
    notificationTag,
    beforeCloseScreen,
  }, null, 2));

  const subscriptionId = psql(`SELECT ps.id::text FROM push_subscriptions ps JOIN users u ON u.id = ps.user_id WHERE u.email = '${account.email}' LIMIT 1;`);
  if (!subscriptionId) throw new Error('fresh account subscription not found');
  log('closing the page while keeping Chrome alive');
  const dueNow = await page.evaluate(() => { const d = new Date(Date.now() - 60000); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; });
  await page.close();
  const scheduleRequestTime = new Date().toISOString();
  const scheduleResponse = await fetch(`${HOST_ORIGIN}/api/reminders/preferences`, { method: 'PUT', headers: { 'X-API-Key': apiKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled: true, time: dueNow, timezone: preferenceAfterEnable.timezone }) });
  const scheduleBody = await scheduleResponse.text();
  if (!scheduleResponse.ok) throw new Error(`post-close schedule HTTP ${scheduleResponse.status}: ${scheduleBody.slice(0, 160)}`);
  const postClose = JSON.parse(scheduleBody);
  if (!postClose.enabled || !postClose.deliverable) throw new Error('post-close schedule not deliverable');
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'post-close-schedule.json'), JSON.stringify({ dueNow, time: postClose.time, timezone: postClose.timezone, enabled: postClose.enabled, deliverable: postClose.deliverable, updated_at: postClose.updated_at }, null, 2));
  const enableTime = postClose.updated_at || scheduleRequestTime;
  await sleep(5000);

  log('waiting for reminder delivery');
  let deliveryRecord;
  try { deliveryRecord = await waitFor(async () => {
    const json = psql(`SELECT json_build_object('subscription_id', subscription_id::text, 'reminder_date', reminder_date::text, 'status', status, 'attempts', attempts, 'sent_at', COALESCE(to_char(sent_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), ''))::text FROM reminder_deliveries WHERE subscription_id = '${subscriptionId}' AND reminder_date = '${reminderDate}' AND status = 'sent' AND sent_at > '${enableTime}' ORDER BY sent_at DESC LIMIT 1;`);
    if (!json) return null;
    return JSON.parse(json);
  }, 240000, 'fresh server-side reminder delivery'); } catch (error) {
    const timeoutRow = psql(`SELECT json_build_object('subscription_id', subscription_id::text, 'reminder_date', reminder_date::text, 'status', status, 'attempts', attempts, 'claimed_at', claimed_at, 'next_attempt_at', next_attempt_at)::text FROM reminder_deliveries WHERE subscription_id = '${subscriptionId}' AND reminder_date = '${reminderDate}' ORDER BY sent_at DESC NULLS LAST LIMIT 1;`);
    fs.writeFileSync(path.join(ARTIFACT_DIR, 'server-delivery-timeout.json'), timeoutRow || '{}');
    throw error;
  }
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'server-delivery.json'), JSON.stringify(deliveryRecord, null, 2));

  const notificationDump = await waitFor(() => {
    const dump = dumpsysNotification('com.android.chrome', 'notification-dumpsys.txt');
    return matchingNotificationRecord(dump, notificationTag) ? dump : null;
  }, 300000, 'Chrome reminder notification');
  if (!matchingNotificationRecord(notificationDump, notificationTag)) {
    throw new Error(`notification dump does not include expected tag ${notificationTag}`);
  }
  log('locating notification bounds');
  adb(['shell', 'cmd', 'statusbar', 'expand-notifications']);
  const uiDump = await waitFor(() => {
    const xml = captureUiDump();
    const column = (xml || '').match(/<node[^>]*resource-id="android:id\/notification_main_column"[^>]*>[\s\S]*?<\/node>/);
    const title = /text="217"/.test(column ? column[0] : '');
    const body = /text="Hora de registrar seu anticoncepcional • Time to record your medication"/.test(column ? column[0] : '');
    return title && body ? xml : null;
  }, 60000, 'exact reminder notification shade UI');
  const notificationScreen = captureScreen('02-notification-shade.png');
  const column = uiDump.match(/<node[^>]*resource-id="android:id\/notification_main_column"[^>]*>[\s\S]*?<\/node>/)?.[0] || '';
  const bounds = parseBounds(column, ['217']);
  if (!bounds) throw new Error('exact reminder notification title bounds not found in notification shade UI');
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'notification-uiautomator.xml'), uiDump);
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'click-target.json'), JSON.stringify({
    notificationTag,
    bounds,
  }, null, 2));
  adb(['shell', 'input', 'tap', String(bounds.centerX || bounds.x), String(bounds.centerY || bounds.y)]);

  await sleep(4000);
  const reopenedScreen = captureScreen('03-notification-click-reopened.png');
  const reopenedBrowser = await connectBrowser();
  const reopenedContext = reopenedBrowser.contexts()[0];
  await waitFor(async () => {
    const pages = reopenedContext.pages();
    const match = pages.find((candidate) => candidate.url() === `${ORIGIN}/?reminder=1`);
    if (!match) return null;
    const info = await match.evaluate(() => ({ url: location.href, secureContext: window.isSecureContext }));
    if (!info.secureContext) return null;
    return info;
  }, 30000, 'Chrome reopening the reminder page');

  const reopenedPage = reopenedContext.pages().find((candidate) => candidate.url() === `${ORIGIN}/?reminder=1`);
  const reopenedPageState = reopenedPage ? await reopenedPage.evaluate(() => ({
    url: location.href,
    secureContext: window.isSecureContext,
    title: document.title,
  })) : null;

  const postClickDump = dumpsysNotification(notificationTag, 'notification-dumpsys-after-click.txt');
  if (matchingNotificationRecord(postClickDump, notificationTag)) throw new Error('reminder notification remained after click');
  const summary = {
    emulator: emulatorInfo(),
    chromeVersion: chromeVersion(),
    browserClock,
    envBefore,
    statusAfterEnable,
    preferenceAfterEnable,
    deliveryRecord,
    notificationTag,
    notificationDumpPath: path.join(ARTIFACT_DIR, 'notification-dumpsys.txt'),
    notificationScreen,
    notificationScreenAfterClick: reopenedScreen,
    beforeCloseScreen,
    clickTarget: bounds,
    reopenedPageState,
    postClickDumpPath: path.join(ARTIFACT_DIR, 'notification-dumpsys-after-click.txt'),
    apiKeyPresent: false,
  };
  fs.writeFileSync(path.join(ARTIFACT_DIR, 'summary.json'), JSON.stringify(summary, null, 2));

  log('delivery verified; cleaning up Chrome and emulator state');
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
