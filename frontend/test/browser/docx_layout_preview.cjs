// Run with node; see web/docx_viewer/README.md for the isolated test dependency.
// This exercises the real renderer in a sandboxed Chromium frame, without Django.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { once } = require('node:events');
const root = path.resolve(__dirname, '../../..');
const web = path.join(root, 'frontend/web');
const JSZip = require(path.join(web, 'docx_viewer/vendor/jszip-3.10.2.min.js'));
let chromium;
try {
  ({ chromium } = require('playwright-core'));
} catch {
  ({ chromium } = require(path.join(root, '.tmp/docx-qa/node_modules/playwright-core')));
}

async function fixture(continuous = false) {
  const zip = new JSZip();
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  zip.file('[Content_Types].xml', `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="xml" ContentType="application/xml"/>
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="png" ContentType="image/png"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
    <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
  </Types>`);
  const relationships = entries => `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${entries}</Relationships>`;
  zip.file('_rels/.rels', relationships(`<Relationship Id="doc" Type="${rel}/officeDocument" Target="word/document.xml"/>`));
  zip.file('word/_rels/document.xml.rels', relationships(`
    <Relationship Id="styles" Type="${rel}/styles" Target="styles.xml"/>
    <Relationship Id="header" Type="${rel}/header" Target="header1.xml"/>
    <Relationship Id="footer" Type="${rel}/footer" Target="footer1.xml"/>
    <Relationship Id="link" Type="${rel}/hyperlink" Target="https://example.invalid/private-document" TargetMode="External"/>
    <Relationship Id="html" Type="${rel}/aFChunk" Target="unsafe.html"/>`));
  zip.file('word/styles.xml', `<w:styles xmlns:w="${w}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Book Antiqua" w:hAnsi="Book Antiqua"/><w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>`);
  zip.file('word/document.xml', `<w:document xmlns:w="${w}" xmlns:r="${rel}"><w:body>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:i/></w:rPr><w:t>Weekly report title</w:t></w:r></w:p>
    <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="3600"/></w:tabs></w:pPr><w:r><w:t>Team Name:</w:t><w:tab/><w:t>Section:</w:t></w:r></w:p>
    <w:tbl><w:tblPr><w:tblW w:w="8000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/><w:gridCol w:w="4000"/></w:tblGrid>
      <w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>Merged table heading</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>Task / Activity</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Output / Evidence</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
    <w:p><w:r><w:br w:type="page"/></w:r></w:p>
    <w:p><w:r><w:t>Reviewed by:</w:t></w:r></w:p>
    <w:p><w:hyperlink r:id="link"><w:r><w:t>Document link</w:t></w:r></w:hyperlink></w:p>
    <w:altChunk r:id="html"/>
    <w:sectPr><w:headerReference w:type="default" r:id="header"/><w:footerReference w:type="default" r:id="footer"/>
      <w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/>
    </w:sectPr>
  </w:body></w:document>`);
  zip.file('word/header1.xml', `<w:hdr xmlns:w="${w}" xmlns:r="${rel}" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
    <w:p><w:r><w:t>USTP TEST HEADER</w:t></w:r></w:p>
    <w:p><w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="304800"/><a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="logo"/></pic:blipFill><pic:spPr><a:xfrm><a:ext cx="914400" cy="304800"/></a:xfrm></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
  </w:hdr>`);
  zip.file('word/_rels/header1.xml.rels', relationships(`<Relationship Id="logo" Type="${rel}/image" Target="media/logo.png"/>`));
  zip.file('word/media/logo.png', 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRuoAAAAASUVORK5CYII=', {base64: true});
  zip.file('word/footer1.xml', `<w:ftr xmlns:w="${w}"><w:p><w:r><w:t>TEST FOOTER</w:t></w:r></w:p></w:ftr>`);
  zip.file('word/unsafe.html', '<script>parent.postMessage("UNSAFE", "*")</script><p>UNSAFE HTML CONTENT</p>');
  if (continuous) {
    const xml = await zip.file('word/document.xml').async('string');
    zip.file('word/document.xml', xml.replace('<w:br w:type="page"/>', '</w:r></w:p>' +
      Array.from({length: 70}, (_, i) => `<w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>Flow paragraph ${i} stays in the document.</w:t></w:r></w:p>`).join('') + '<w:p><w:r>'));
  }
  return zip.generateAsync({type: 'nodebuffer'});
}

async function main() {
  const sample = process.argv[2];
  const bytes = await fixture();
  const flow = await fixture(true);
  const harness = `<!doctype html><html><head><style>html,body,iframe {margin:0;width:100%;height:100%;border:0;overflow:hidden}</style></head><body>
    <iframe title="DOCX test" sandbox="allow-scripts" src="/docx_viewer/index.html#qa-channel"></iframe>
    <script>
      window.messages = [];
      addEventListener('message', async e => {
        if (e.source !== document.querySelector('iframe').contentWindow) return;
        try { const m = JSON.parse(e.data); messages.push({...m, origin:e.origin});
          if (m.type === 'ready') {
            const blob = await (await fetch(location.pathname === '/sample' ? '/sample.docx' : location.pathname === '/invalid' ? '/invalid.docx' : location.pathname === '/flow' ? '/flow.docx' : '/fixture.docx')).blob();
            e.source.postMessage({channel:'qa-channel',type:'render',blob}, '*');
          }
        } catch (_) {}
      });
    </script></body></html>`;
  const types = {'.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css'};
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (['/', '/sample', '/invalid', '/flow'].includes(url.pathname)) {
      res.setHeader('Content-Type', 'text/html'); return res.end(harness);
    }
    if (url.pathname === '/fixture.docx') return res.end(bytes);
    if (url.pathname === '/flow.docx') return res.end(flow);
    if (url.pathname === '/invalid.docx') return res.end('Invalid archive');
    if (url.pathname === '/sample.docx' && sample) return res.end(fs.readFileSync(sample));
    const target = path.resolve(web, '.' + url.pathname);
    if (!target.startsWith(path.join(web, 'docx_viewer') + path.sep) || !fs.existsSync(target)) {
      res.writeHead(404); return res.end();
    }
    res.setHeader('Content-Type', types[path.extname(target)] || 'application/octet-stream');
    res.end(fs.readFileSync(target));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;
  let browser;
  try {
    browser = await chromium.launch({
      executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
    });
    const page = await browser.newPage({viewport: {width: 1100, height: 900}});
    const errors = [], remote = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => {if (!r.url().startsWith(origin) && !r.url().startsWith('data:')) remote.push(r.url());});
    await page.goto(origin);
    await page.waitForFunction(() => messages.some(m => m.type === 'rendered'), {timeout: 20000});
    const frame = page.frames().find(f => f.url().includes('/docx_viewer/'));
    assert.equal(await frame.locator('section.docx').count(), 2);
    assert.equal(await frame.locator('header').filter({hasText: 'USTP TEST HEADER'}).count(), 2);
    assert.equal(await frame.locator('footer').filter({hasText: 'TEST FOOTER'}).count(), 2);
    assert.equal(await frame.locator('td[colspan="2"]').textContent(), 'Merged table heading');
    assert.equal(await frame.locator('header img').count(), 2);
    assert(await frame.locator('header img').first().evaluate(img => img.complete && img.naturalWidth > 0));
    const title = frame.getByText('Weekly report title', {exact: true});
    assert.equal(await title.evaluate(e => getComputedStyle(e.closest('p')).textAlign), 'center');
    assert.equal(await title.evaluate(e => getComputedStyle(e).fontStyle), 'italic');
    assert.match(await title.evaluate(e => getComputedStyle(e).fontFamily), /Book Antiqua/);
    assert.equal(await frame.locator('iframe, script:not([src])').count(), 0);
    assert(!(await frame.locator('body').textContent()).includes('UNSAFE HTML CONTENT'));
    assert(await page.evaluate(() => messages.every(m => m.origin === 'null')));
    await frame.getByText('Document link', {exact: true}).evaluate(e => e.click());
    assert(frame.url().endsWith('#qa-channel'));
    await page.setViewportSize({width: 390, height: 750});
    await page.waitForFunction(() => messages.filter(m => m.type === 'layout').at(-1)?.scale < 0.5);
    assert(await frame.locator('#viewport').evaluate(e => e.scrollWidth <= e.clientWidth + 1));
    await page.evaluate(() => document.querySelector('iframe').contentWindow.postMessage({channel:'qa-channel',type:'zoom',scale:1.5}, '*'));
    await page.waitForFunction(() => messages.filter(m => m.type === 'layout').at(-1)?.scale === 1.5);
    assert(await frame.locator('#viewport').evaluate(e => e.scrollWidth > e.clientWidth));
    await page.evaluate(() => document.querySelector('iframe').contentWindow.postMessage({channel:'qa-channel',type:'theme',dark:true}, '*'));
    await frame.waitForFunction(() => document.documentElement.dataset.dark === 'true');
    assert.deepEqual(remote, []);
    assert.deepEqual(errors, []);
    console.log('PASS: original styles, header/footer images, merged tables, two pages, sandbox, blocked HTML/navigation, responsive fit, zoom, dark canvas.');
    await page.goto(origin + '/invalid');
    await page.waitForFunction(() => messages.some(m => m.type === 'error'));
    console.log('PASS: unreadable DOCX reports failure for the Flutter fallback.');
    await page.setViewportSize({width: 1100, height: 900});
    await page.goto(origin + '/flow');
    await page.waitForFunction(() => messages.some(m => m.type === 'rendered'));
    const flowing = page.frames().find(f => f.url().includes('/docx_viewer/'));
    const count = await flowing.locator('section.docx').count();
    assert(count >= 2);
    assert.equal(await flowing.locator('header').count(), count);
    assert.equal(await flowing.locator('footer').count(), count);
    for (let i = 0; i < 70; i++) {
      assert.equal(await flowing.getByText(`Flow paragraph ${i} stays in the document.`, {exact: true}).count(), 1);
    }
    assert(await flowing.locator('section.docx').evaluateAll(sections => sections.every(s => {
      const article = s.querySelector('article');
      const last = article.lastElementChild;
      return last.getBoundingClientRect().bottom <= s.querySelector('footer').getBoundingClientRect().top + 1;
    })));
    console.log('PASS: documents without saved breaks paginate with repeated headers/footers and retain all 70 paragraphs.');
    if (sample) {
      await page.setViewportSize({width: 1100, height: 1000});
      await page.goto(origin + '/sample');
      await page.waitForFunction(() => messages.some(m => m.type === 'rendered'));
      const actual = page.frames().find(f => f.url().includes('/docx_viewer/'));
      assert((await actual.locator('article').allTextContents()).join('').includes('CAPSTONE PROJECT WEEKLY ACCOMPLISHMENT REPORT'));
      assert(await actual.locator('header img, header svg').count() > 0);
      const directory = path.join(root, '.tmp/docx-layout-preview');
      fs.mkdirSync(directory, {recursive: true});
      await page.screenshot({path: path.join(directory, 'weekly-report-desktop.png')});
      console.log('PASS: actual weekly report; page count:', await actual.locator('section.docx').count());
      assert.equal(await actual.locator('section.docx').count(), 2);
      assert((await actual.locator('section.docx').nth(1).textContent()).includes('Reviewed by:'));
      assert(await actual.locator('section.docx').first().evaluate(e => {
        const image = e.querySelector('header img').getBoundingClientRect();
        const paper = e.getBoundingClientRect();
        return image.left >= paper.left - 2 && image.right <= paper.right + 2;
      }));
      await actual.locator('#viewport').evaluate(e => e.scrollTop = e.scrollHeight);
      await page.screenshot({path: path.join(directory, 'weekly-report-second-page.png')});
      await page.setViewportSize({width: 390, height: 750});
      await page.waitForFunction(() => messages.filter(m => m.type === 'layout').at(-1)?.scale < 0.5);
      await actual.locator('#viewport').evaluate(e => e.scrollTop = 0);
      await page.screenshot({path: path.join(directory, 'weekly-report-phone.png')});
    }
  } finally {
    await browser?.close();
    server.close();
  }
}
main().catch(e => {console.error(e); process.exitCode = 1;});
