const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const baseUrl = process.env.BASE_URL || "http://localhost:8080";
const outputDir = process.env.OUTPUT_DIR || "/artifacts/screenshots";

fs.mkdirSync(outputDir, { recursive: true });

async function newMobilePage(browser, width, height, sessionToken = "") {
  const context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: 1,
    isMobile: true,
    hasTouch: true,
  });
  if (sessionToken) {
    await context.addCookies([{ name: "217_session", value: sessionToken, url: baseUrl }]);
  }
  const page = await context.newPage();
  await page.goto(baseUrl, { waitUntil: "networkidle" });
  return { context, page };
}

async function waitForMain(page) {
  await page.locator(".today-card").waitFor({ state: "visible" });
  await page.locator("#calendar-scroll").waitFor({ state: "visible" });
}

async function checkBranding(page) {
  const link = page.getByRole("link", { name: /Google/ });
  assert.equal(await link.getAttribute("href"), "/api/auth/google");
  const img = link.locator("img");
  assert.equal(await img.getAttribute("src"), "/google-signin.png");
  await img.evaluate(el => el.decode());
  assert.ok(await img.evaluate(el => el.naturalWidth > 0));
  await page.getByRole("button", { name: "Language / Idioma" }).click();
  assert.equal(await link.getAttribute("aria-label"), "Continue with Google");
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
}

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined });
  const sessionToken = process.env.SESSION_TOKEN;
  assert.ok(sessionToken, "SESSION_TOKEN from backend/cmd/e2esession is required");

  try {
    const small = await newMobilePage(browser, 320, 568);
    await small.page.getByRole("link", { name: /Google/ }).waitFor({ state: "visible" });
    await checkBranding(small.page);
    await small.page.screenshot({ path: path.join(outputDir, "auth-320x568.png") });
    await small.context.close();

    const auth = await newMobilePage(browser, 360, 800);
    await auth.page.getByRole("link", { name: /Google/ }).waitFor({ state: "visible" });
    await checkBranding(auth.page);
    await auth.page.screenshot({ path: path.join(outputDir, "auth-360x800.png") });
    await auth.context.close();

    const primary = await newMobilePage(browser, 360, 800, sessionToken);
    const page = primary.page;
    await waitForMain(page);
    await page.screenshot({ path: path.join(outputDir, "main-today-360x800.png") });

    await page.getByRole("button", { name: "Status de hoje", exact: true }).click();
    await page.getByRole("dialog").waitFor({ state: "visible" });
    await page.getByRole("button", { name: "✓ Tomei", exact: true }).click();
    await page.locator("#day-notes").fill("Tomado com água após o café da manhã.");
    await page.screenshot({ path: path.join(outputDir, "day-notes-dialog-360x800.png") });
    await page.getByRole("button", { name: "Salvar", exact: true }).click();
    await page.getByRole("dialog").waitFor({ state: "detached" });

    const today = await page.evaluate(() => {
      const now = new Date();
      const pad = (value) => String(value).padStart(2, "0");
      return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    });
    const yesterday = await page.evaluate(() => {
      const date = new Date();
      date.setDate(date.getDate() - 1);
      const pad = (value) => String(value).padStart(2, "0");
      return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    });
    const yesterdayButton = page.locator(`button.day[aria-label^="${yesterday}: "]`);
    await yesterdayButton.scrollIntoViewIfNeeded();
    await yesterdayButton.click();
    await page.getByRole("dialog").waitFor({ state: "visible" });
    await page.getByRole("button", { name: "✗ Não tomei", exact: true }).click();
    await page.getByRole("button", { name: "Salvar", exact: true }).click();
    await page.getByRole("dialog").waitFor({ state: "detached" });

    const todayButton = page.locator(`button.day[aria-label^="${today}: "]`);
    await todayButton.scrollIntoViewIfNeeded();
    await yesterdayButton.scrollIntoViewIfNeeded();
    try {
      await page.waitForFunction(
        ({ todayDate, yesterdayDate }) => {
          const todayElement = document.querySelector(`button.day[aria-label^="${todayDate}: "]`);
          const yesterdayElement = document.querySelector(`button.day[aria-label^="${yesterdayDate}: "]`);
          const legendElement = document.querySelector('section.status-legend[aria-label="Legenda de status"]');
          return todayElement?.classList.contains("day-taken") &&
            yesterdayElement?.classList.contains("day-missed") &&
            legendElement !== null;
        },
        { todayDate: today, yesterdayDate: yesterday },
        { timeout: 10000 },
      );
    } catch (error) {
      throw new Error(`Calendar status markers did not render in time: ${error.message}`);
    }
    await todayButton.waitFor({ state: "visible" });
    await yesterdayButton.waitFor({ state: "visible" });
    assert.match(await todayButton.getAttribute("class"), /day-taken/);
    assert.equal(await todayButton.locator(".day-indicator").textContent(), "✓");
    assert.match(await todayButton.getAttribute("aria-label"), /Tomado/);
    assert.match(await yesterdayButton.getAttribute("class"), /day-missed/);
    assert.equal(await yesterdayButton.locator(".day-indicator").textContent(), "✕");
    assert.match(await yesterdayButton.getAttribute("aria-label"), /Não tomado/);
    const legend = page.locator('section.status-legend[aria-label="Legenda de status"]');
    await legend.waitFor({ state: "visible" });
    const legendText = (await legend.textContent()) || "";
    assert.match(legendText, /Tomado/);
    assert.match(legendText, /Não tomado/);
    assert.match(legendText, /Não registrado/);
    await legend.scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(outputDir, "calendar-status-markers-360x800.png") });

    await page.getByRole("button", { name: "Opções", exact: true }).click();
    assert.equal(await page.locator("aside button").count(), 1);
    assert.equal(await page.locator("aside button").innerText(), "Sair");
    await page.getByRole("button", { name: "Opções", exact: true }).click();
    const calendarScroll = await page.locator("#calendar-scroll").evaluate(el => el.scrollTop);
    await page.locator("#open-settings").click();
    await page.locator(".today-card").waitFor({ state: "hidden" });
    await page.locator("#reminder-time").waitFor({ state: "visible", timeout: 15000 });
    await page.screenshot({ path: path.join(outputDir, "reminder-settings-360x800.png") });
    await page.getByRole("button", { name: "Modo claro", exact: true }).click();
    assert.equal(await page.locator(".app.light").count(), 1);
    await page.getByRole("button", { name: "English", exact: true }).click();
    await page.getByRole("heading", { name: "Settings", exact: true }).waitFor();
    await page.getByRole("button", { name: "Dark mode", exact: true }).click();
    assert.equal(await page.locator(".app.dark").count(), 1);
    await page.getByRole("button", { name: "← Back to calendar", exact: true }).click();
    await waitForMain(page);
    assert.ok(Math.abs(await page.locator("#calendar-scroll").evaluate(el => el.scrollTop) - calendarScroll) < 2);
    await page.route("**/api/auth/logout", route => route.fulfill({ status: 503, contentType: "application/json", body: '{"error":"retry"}' }));
    await page.getByRole("button", { name: "Options", exact: true }).click();
    await page.locator("aside button").click();
    await page.getByRole("alert").filter({ hasText: "Could not log out" }).waitFor();
    await waitForMain(page);
    assert.equal(await page.locator("aside button:enabled").count(), 1);
    await primary.context.close();

    const stress = await newMobilePage(browser, 320, 568, sessionToken);
    await waitForMain(stress.page);
    await stress.page.screenshot({ path: path.join(outputDir, "main-today-320x568.png") });
    await stress.page.locator("#open-settings").click();
    await stress.page.locator("#reminder-time").waitFor();
    assert.ok(await stress.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await stress.page.getByRole("button", { name: "← Voltar ao calendário", exact: true }).click();
    await waitForMain(stress.page);
    await stress.context.close();

    console.log(`Captured seven mobile screenshots in ${outputDir}`);
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
