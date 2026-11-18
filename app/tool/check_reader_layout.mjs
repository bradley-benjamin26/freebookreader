// Checks that the web reader's iframe ends above the page controls.
// Needs Playwright: `npm i playwright` in a scratch folder (not in this repo), then
// NODE_PATH=<scratch>/node_modules node app/tool/check_reader_layout.mjs [--phone]
// with the web build served on http://localhost:8080. PW_CHROMIUM = a Chromium binary, if set.
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

const phone = process.argv.includes('--phone');
const browser = await chromium.launch({ executablePath: process.env.PW_CHROMIUM || undefined });
const page = await browser.newPage({ viewport: phone ? { width: 390, height: 844 } : { width: 1280, height: 800 } });
try {
  await page.goto('http://localhost:8080/');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.getByRole('button', { name: 'Frankenstein', exact: true }).click();
  const count = page.getByText(/results? for/).first();
  await count.waitFor({ timeout: 30000 });
  const box = await count.boundingBox();
  await page.mouse.click(box.x + 40, box.y + box.height + 50);
  await page.getByRole('button', { name: /^Read / }).first().click({ timeout: 30000 });
  await page.waitForTimeout(8000);
  const bottom = await page.evaluate(() => document.querySelector('flt-platform-view iframe').getBoundingClientRect().bottom);
  const next = await page.getByRole('button', { name: 'Next page' }).boundingBox();
  if (next && bottom <= next.y) {
    console.log('OK');
  } else {
    console.log(`FAIL iframe bottom ${bottom} > Next page top ${next?.y}`);
    process.exitCode = 1;
  }
} finally {
  await browser.close();
}
