/* global JSZip */
// Browser layout corrections around the renderer's stable renderAsync API.
window.docxLayout = (() => {
  "use strict";
  const drawing = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing";
  const picture = "http://schemas.openxmlformats.org/drawingml/2006/main";
  const relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
  const first = (node, ns, name) => node.getElementsByTagNameNS(ns, name)[0];
  const parse = text => new DOMParser().parseFromString(text, "application/xml");

  async function anchors(data) {
    const zip = await JSZip.loadAsync(data);
    const result = [];
    for (const part of Object.values(zip.files)) {
      if (!/^word\/(document|header\d+|footer\d+)\.xml$/.test(part.name)) continue;
      const xml = parse(await part.async("string"));
      const relPath = part.name.replace(/([^/]+)$/, "_rels/$1.rels");
      if (!zip.file(relPath)) continue;
      const rels = parse(await zip.file(relPath).async("string"));
      const scope = part.name.includes("header") ? "header" : part.name.includes("footer") ? "footer" : "article";
      for (const anchor of xml.getElementsByTagNameNS(drawing, "anchor")) {
        if (!first(anchor, drawing, "wrapNone")) continue;
        const horizontal = first(anchor, drawing, "positionH");
        const vertical = first(anchor, drawing, "positionV");
        const x = horizontal?.getAttribute("relativeFrom") === "page" ? first(horizontal, drawing, "posOffset") : null;
        const y = vertical?.getAttribute("relativeFrom") === "page" ? first(vertical, drawing, "posOffset") : null;
        if (!x && !y) continue;
        const id = first(anchor, picture, "blip")?.getAttributeNS(relationship, "embed");
        const rel = Array.from(rels.documentElement.children).find(r => r.getAttribute("Id") === id);
        if (!rel || rel.getAttribute("TargetMode") === "External") continue;
        const target = new URL(rel.getAttribute("Target"), `https://document.local/${part.name}`).pathname.slice(1);
        const file = zip.file(target);
        if (!file) continue;
        result.push({
          scope,
          image: await file.async("base64"),
          x: x ? Number(x.textContent) / 9525 : null,
          y: y ? Number(y.textContent) / 9525 : null,
        });
      }
    }
    return result;
  }

  function positionMargins(section) {
    const style = getComputedStyle(section);
    // Word headers occupy the margin area; blank header paragraphs must not
    // push the document body below the configured top margin.
    for (const margin of section.querySelectorAll(":scope > header, :scope > footer")) {
      margin.style.position = "absolute";
      margin.style.left = style.paddingLeft;
      margin.style.right = style.paddingRight;
      if (margin.tagName === "HEADER") margin.style.top = style.paddingTop;
      else margin.style.bottom = style.paddingBottom;
    }
  }

  function lineSpacing(pages) {
    const metrics = new Map();
    const probe = document.createElement("div");
    probe.textContent = "M";
    probe.style.cssText = "position:absolute;visibility:hidden;line-height:normal";
    document.body.appendChild(probe);
    for (const p of pages.querySelectorAll("p")) {
      // Word's auto line spacing multiplies the font's natural line height,
      // whereas CSS numeric line-height multiplies its em size.
      if (!/^\d+(\.\d+)?$/.test(p.style.lineHeight)) continue;
      const style = getComputedStyle(p);
      const key = `${style.fontFamily}|${style.fontSize}|${style.fontWeight}|${style.fontStyle}`;
      if (!metrics.has(key)) {
        probe.style.fontFamily = style.fontFamily;
        probe.style.fontSize = style.fontSize;
        probe.style.fontWeight = style.fontWeight;
        probe.style.fontStyle = style.fontStyle;
        metrics.set(key, probe.offsetHeight);
      }
      const height = metrics.get(key) * Number(p.style.lineHeight);
      p.style.lineHeight = `${height}px`;
      if (!p.textContent && !p.querySelector("img,svg")) p.style.minHeight = `${height}px`;
    }
    probe.remove();
  }

  function paintedBounds(margin) {
    if (!margin) return [];
    return Array.from(margin.querySelectorAll("img,svg,p"))
      .filter(e => e.tagName !== "P" || e.textContent.trim())
      .map(e => e.getBoundingClientRect());
  }

  function clearHeader(section) {
    const article = section.querySelector(":scope > article");
    if (!article) return;
    const ink = paintedBounds(section.querySelector(":scope > header"));
    if (!ink.length) return;
    const bottom = Math.max(...ink.map(r => r.bottom));
    const overlap = bottom - article.getBoundingClientRect().top;
    if (overlap > 0) {
      const gap = parseFloat(getComputedStyle(article).fontSize) || 16;
      article.style.paddingTop = `${overlap + gap}px`;
    }
  }

  function positionAnchors(section, positions) {
    const page = section.getBoundingClientRect();
    for (const img of section.querySelectorAll("img")) {
      const candidates = positions.filter(p => img.closest(p.scope) && img.src.endsWith("," + p.image));
      // Leave ambiguous repeated-image positions to the renderer.
      if (!candidates.length || candidates.some(p => p.x !== candidates[0].x || p.y !== candidates[0].y)) continue;
      const pos = candidates[0];
      const container = img.parentElement;
      if (container.tagName !== "DIV" || container.style.position !== "relative") continue;
      const image = img.getBoundingClientRect();
      const style = getComputedStyle(container);
      if (pos.x !== null && Number.isFinite(pos.x)) {
        container.style.left = `${(parseFloat(style.left) || 0) + page.left + pos.x - image.left}px`;
      }
      if (pos.y !== null && Number.isFinite(pos.y)) {
        container.style.top = `${(parseFloat(style.top) || 0) + page.top + pos.y - image.top}px`;
      }
    }
  }

  function paginate(section) {
    const articles = section.querySelectorAll(":scope > article");
    if (articles.length !== 1) return;
    const article = articles[0];
    const style = getComputedStyle(section);
    const height = parseFloat(style.minHeight);
    const page = section.getBoundingClientRect();
    const footer = paintedBounds(section.querySelector(":scope > footer"));
    const bottom = footer.length
      ? Math.min(height - parseFloat(style.paddingBottom), height - page.bottom + Math.min(...footer.map(r => r.top)))
      : height - parseFloat(style.paddingBottom);
    const available = bottom - parseFloat(style.paddingTop);
    // Keep complex column/note layouts intact. Oversized indivisible blocks
    // can grow their page instead of being clipped or dropping any content.
    if (!(available > 0) || getComputedStyle(article).columnCount !== "auto" ||
        section.querySelector(":scope > ol") || article.offsetHeight <= available + 1) return;
    const template = section.cloneNode(true);
    const blocks = Array.from(article.childNodes);
    article.replaceChildren();
    let current = section;
    let content = article;
    for (const block of blocks) {
      const hadContent = content.childNodes.length > 0;
      content.appendChild(block);
      if (content.offsetHeight <= available + 1 || !hadContent) continue;
      block.remove();
      const carry = [];
      // Keep a short label and its following table together at a page boundary
      // (for example, a review/signature block or a table section heading).
      if (block.nodeName === "TABLE") {
        for (let previous = content.lastElementChild; previous?.tagName === "P";) {
          carry.unshift(previous);
          if (previous.textContent.trim()) break;
          previous = previous.previousElementSibling;
        }
        const label = carry[0];
        if (!label?.textContent.trim() || label.textContent.length > 160 ||
            carry.reduce((sum, p) => sum + p.offsetHeight, 0) > available / 4) carry.length = 0;
      }
      if (carry.length === content.children.length) {
        content.appendChild(block);
        continue;
      }
      for (const element of carry) element.remove();
      const next = template.cloneNode(true);
      const nextContent = next.querySelector(":scope > article");
      nextContent.replaceChildren(...carry, block);
      current.after(next);
      current = next;
      content = nextContent;
    }
  }

  async function prepare(pages, data) {
    const positions = await anchors(data);
    lineSpacing(pages);
    for (const section of Array.from(pages.querySelectorAll(":scope > section.docx"))) {
      positionMargins(section);
      positionAnchors(section, positions);
      clearHeader(section);
      paginate(section);
    }
  }
  return { prepare };
})();
