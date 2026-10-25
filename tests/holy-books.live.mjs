/*
 * Drives apps/holy-books.html in a real browser against a LIVE appliance with the vocabulary and at least
 * the Bible, the Quran and the Tanakh installed, their chapter documents ingested, and asserts what a
 * reader sees.
 *
 * Live rather than stubbed: the page's worth is in what the views answer across scriptures — a scripture
 * that is silent on a topic, a summary that cites its verses, a parallel that opens the other scripture —
 * and a stub would answer all of it instantly and correctly whatever the engine did.
 *
 *   APPLIANCE_URL=http://localhost:11043 APPLIANCE_USER=… APPLIANCE_PASSWORD=… node tests/holy-books.live.mjs
 *   APPLIANCE_AUTH='Basic …' node tests/holy-books.live.mjs        # or a ready Authorization header
 *
 * SHOTS=dir writes screenshots there. Needs `playwright` resolvable. Exits non-zero on any failed check.
 */
import { chromium } from 'playwright';

const base = process.env.APPLIANCE_URL ?? 'http://localhost:11043';
const url = `${base}/apps/scripture-vocabulary/holy-books.html`;
const authorization = process.env.APPLIANCE_AUTH ??
  (process.env.APPLIANCE_USER && process.env.APPLIANCE_PASSWORD
    ? 'Basic ' + Buffer.from(`${process.env.APPLIANCE_USER}:${process.env.APPLIANCE_PASSWORD}`).toString('base64')
    : null);
if (!authorization) {
  console.error('Set APPLIANCE_AUTH, or APPLIANCE_USER and APPLIANCE_PASSWORD.');
  process.exit(2);
}
const shots = process.env.SHOTS;

let failures = 0;
function check(what, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
}

const browser = await chromium.launch();
/* Sent up front: the appliance redirects an unauthenticated page to its login rather than answering 401. */
const context = await browser.newContext({ extraHTTPHeaders: { Authorization: authorization }, viewport: { width: 1360, height: 900 } });
const page = await context.newPage();
const consoleErrors = [];
page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', (e) => consoleErrors.push(String(e)));

/* The reader sets its title at once and its verses when they arrive, so "opened" means both: this title, and
   verses under it rather than the placeholder. */
const opened = (title) => page.waitForFunction((t) =>
  document.querySelector('#reader .rhead h2')?.textContent === t && !!document.querySelector('#reader .rbody p .vn'),
  title, { timeout: 20000 });

const column = (name) => page.locator('article.col', { has: page.locator('h2', { hasText: name }) }).first();

try {
  await page.goto(url, { waitUntil: 'networkidle' });
  check('manifest preflight passes (no problem shown)', !(await page.locator('.problem').count()));

  /* The topic, from an example: a word three scriptures use and one never does. */
  const t0 = Date.now();
  await page.getByRole('button', { name: 'circumcision' }).click();
  const cols = await page.locator('article.col').count();
  check('one column per installed scripture', cols >= 3, `${cols}`);

  await page.locator('.bar').first().waitFor({ timeout: 30000 });
  const bars = await page.locator('.bar').count();
  check('the overview has a bar per scripture', bars === cols, `${bars} bars`);
  const quranBar = await page.locator('.bar', { hasText: 'Quran' }).first().textContent();
  check('the Quran bar counts no verses', /\b0 of /.test(quranBar), quranBar.replace(/\s+/g, ' '));

  const quran = column('Quran');
  await quran.locator('.silent').first().waitFor({ timeout: 30000 });
  check('the Quran column says no verse uses the word', /No verse uses/.test(await quran.textContent()));

  const bible = column('Bible');
  await bible.locator('.vs').first().waitFor({ timeout: 30000 });
  check('the Bible column lists verses using the word, marked', (await bible.locator('.vs mark').count()) > 0);
  await bible.locator('.ch').first().waitFor({ timeout: 45000 });
  check('the Bible column lists its nearest chapters by meaning', (await bible.locator('.ch').count()) >= 1,
    await bible.locator('.ch .nm').first().textContent());

  await bible.locator('.summary li, .summary p').first().waitFor({ timeout: 120000 });
  const summaryMs = Date.now() - t0;
  const bibleSummary = await bible.locator('.summary').textContent();
  check('the Bible summary arrives and cites Genesis 17', /Genesis 17/.test(bibleSummary), `${summaryMs} ms`);
  check('the summary says what it was drawn from', /verses? using/.test(bibleSummary));
  const quranSummary = await quran.locator('[id$="-summary"]').textContent();
  check('the Quran summary is silent, not invented', /nothing in those words/.test(quranSummary));
  check('…and offers to look by meaning', (await quran.getByRole('button', { name: 'Look by meaning instead' }).count()) === 1);
  if (shots) await page.screenshot({ path: `${shots}/holy-books-wide.png`, fullPage: true });

  /* The reader: a Bible verse opens its chapter, its verse marked, and a parallel opens the Tanakh's. */
  const first = bible.locator('.vs').first();
  const firstChapter = await first.getAttribute('data-chapter');
  await first.click();
  await opened(firstChapter);
  const title = await page.locator('#reader .rhead h2').textContent();
  check('a verse opens its chapter in the reader', /Genesis 17/.test(title), title);
  check('the verse it was opened from is marked', (await page.locator('#reader p.hit').count()) === 1);
  const parallel = page.locator('#reader .par .link').first();
  const hasParallel = (await parallel.count()) > 0;
  check('the chapter shows its parallels in another scripture', hasParallel);
  if (hasParallel) {
    const to = await parallel.getAttribute('data-chapter');
    await parallel.click();
    await opened(to);
    check('a parallel opens the other scripture’s chapter', true, to);
    check('the other scripture carries its original text', (await page.locator('#reader .orig').count()) > 0);
  }
  if (shots) await page.screenshot({ path: `${shots}/holy-books-reader.png` });
  await page.locator('#reader [data-close]').click();

  /* A Quran verse opens its surah by the chapter the search returned, not a name guessed from the reference. */
  await page.locator('#topic').fill('');
  await page.locator('#topic').fill('fasting');
  check('a stem is guessed for the word field', (await page.locator('#term').inputValue()) === 'fast',
    await page.locator('#term').inputValue());
  await page.getByRole('button', { name: 'Compare' }).click();
  await quran.locator('.vs').first().waitFor({ timeout: 30000 });
  const surah = await quran.locator('.vs').first().getAttribute('data-chapter');
  await quran.locator('.vs').first().click();
  await opened(surah);
  check('a Quran verse opens its surah, with the Arabic', (await page.locator('#reader .orig').count()) > 0,
    await page.locator('#reader .rhead h2').textContent());
  await page.locator('#reader [data-close]').click();

  /* Phone width: no sideways scroll, columns stacked. */
  await page.setViewportSize({ width: 390, height: 860 });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('no horizontal scroll at phone width', overflow <= 0, `${overflow}px`);
  if (shots) await page.screenshot({ path: `${shots}/holy-books-phone.png`, fullPage: false });

  check('no console errors', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));
} catch (e) {
  check('the run completed', false, String(e));
} finally {
  await browser.close();
}
process.exit(failures ? 1 : 0);
