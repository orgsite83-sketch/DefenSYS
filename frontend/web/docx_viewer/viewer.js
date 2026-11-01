/* global docx, docxLayout */
(() => {
  "use strict";

  const channel = location.hash.slice(1);
  const viewport = document.getElementById("viewport");
  const pages = document.getElementById("pages");
  const sizer = document.getElementById("sizer");
  let requestedScale = null;
  let rendered = false;
  let rendering = false;

  function send(type, extra = {}) {
    parent.postMessage(JSON.stringify({ channel, type, ...extra }), "*");
  }

  function resize() {
    if (!rendered) return;
    const width = pages.offsetWidth;
    if (!width) return;
    const scale = requestedScale ?? Math.min(1, (viewport.clientWidth - 48) / width);
    const boundedScale = Math.max(0.1, scale);
    pages.style.transform = `scale(${boundedScale})`;
    sizer.style.width = `${width * boundedScale}px`;
    sizer.style.height = `${pages.offsetHeight * boundedScale}px`;
    send("layout", {
      pages: pages.querySelectorAll(":scope > section.docx").length,
      scale: boundedScale,
    });
  }

  async function render(blob) {
    // Each isolated frame renders a single immutable copy of the input.
    if (rendering || rendered) return;
    rendering = true;
    try {
      const data = await blob.arrayBuffer();
      await docx.renderAsync(
        data,
        pages,
        document.getElementById("document-styles"),
        {
          inWrapper: false,
          ignoreWidth: false,
          ignoreHeight: false,
          ignoreFonts: false,
          breakPages: true,
          ignoreLastRenderedPageBreak: false,
          renderHeaders: true,
          renderFooters: true,
          renderFootnotes: true,
          renderEndnotes: true,
          // Do not execute or embed HTML packaged inside a Word document.
          renderAltChunks: false,
          useBase64URL: true,
          experimental: true, // Preserve tab stops used in form templates.
        },
      );
      if (!pages.querySelector("section.docx")) throw new Error("No pages");
      await document.fonts.ready;
      await Promise.all(Array.from(pages.querySelectorAll("img"), (img) =>
        img.decode().catch(() => {})));
      await docxLayout.prepare(pages, data);
      rendered = true;
      resize();
      send("rendered");
    } catch (_) {
      send("error");
    }
  }

  window.addEventListener("message", (event) => {
    if (event.source !== parent || !channel) return;
    const message = event.data;
    if (!message || message.channel !== channel) return;
    if (message.type === "render" && message.blob instanceof Blob) {
      document.documentElement.dataset.dark = String(message.dark === true);
      render(message.blob);
    } else if (message.type === "zoom") {
      requestedScale = typeof message.scale === "number" && Number.isFinite(message.scale)
        ? Math.min(2.5, Math.max(0.25, message.scale)) : null;
      resize();
    } else if (message.type === "theme") {
      document.documentElement.dataset.dark = String(message.dark === true);
    }
  });
  // A preview must never navigate the frame to document-supplied hyperlinks.
  document.addEventListener("click", (event) => {
    if (event.target.closest?.("a")) event.preventDefault();
  }, true);
  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape") send("close");
  });
  new ResizeObserver(resize).observe(viewport);
  new ResizeObserver(resize).observe(pages);
  send("ready");
})();
