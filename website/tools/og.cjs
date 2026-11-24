// Renders the social preview images (public/og/*.jpg) from tools/og/og.html.
// Needs Playwright with Chromium: npx playwright install chromium
const { chromium } = require("playwright");
const path = require("node:path");

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  const template = "file://" + path.join(__dirname, "og", "og.html");
  for (const v of ["home", "default", "features", "pricing"]) {
    await page.goto(`${template}?v=${v}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const out = path.join(__dirname, "..", "public", "og", `${v}.jpg`);
    await page.screenshot({ path: out, type: "jpeg", quality: 88 });
    console.log("wrote", path.relative(process.cwd(), out));
  }
  await browser.close();
})();
