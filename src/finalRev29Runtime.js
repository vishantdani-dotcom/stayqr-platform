const REV29_CLASS = "rev29-neutral-surface";
const ROOT_GUEST = "rev29-page-guests";
const ROOT_MEDIA = "rev29-page-media-manager";

const PRESERVE = [
  [6, 8, 11],    // page background
  [8, 11, 17],   // approved dark field
  [9, 12, 17],   // approved elevated input
  [15, 20, 26],  // approved panel
  [19, 25, 32],  // approved panel-2
  [23, 30, 38],  // approved panel-3
  [39, 48, 58],  // approved line / dark border family
];

const SKIP_TAGS = new Set([
  "BUTTON",
  "A",
  "INPUT",
  "SELECT",
  "TEXTAREA",
  "OPTION",
  "IMG",
  "VIDEO",
  "PICTURE",
  "CANVAS",
  "SVG",
  "PATH",
]);

let scheduled = false;
let lastPage = "";
let lastCount = -1;

function normText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function exactHeading(text) {
  const wanted = text.toLowerCase();

  return [...document.querySelectorAll("h1,h2,h3")]
    .find((el) => normText(el.textContent).toLowerCase() === wanted) || null;
}

function detectPage() {
  const guestHeading = exactHeading("Guests");
  if (guestHeading) {
    return { kind: "guests", heading: guestHeading };
  }

  const mediaHeading = exactHeading("Media Manager");
  if (mediaHeading) {
    return { kind: "media", heading: mediaHeading };
  }

  return null;
}

function parseRgb(value) {
  const match = String(value || "").match(
    /rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)/i
  );

  if (!match) {
    return null;
  }

  return {
    r: Math.round(Number(match[1])),
    g: Math.round(Number(match[2])),
    b: Math.round(Number(match[3])),
    a: match[4] == null ? 1 : Number(match[4]),
  };
}

function near(a, b, tolerance = 2) {
  return Math.abs(a - b) <= tolerance;
}

function isPreserved(c) {
  return PRESERVE.some(
    ([r, g, b]) =>
      near(c.r, r) &&
      near(c.g, g) &&
      near(c.b, b)
  );
}

function shouldNeutralize(c) {
  if (!c || c.a <= 0.05) {
    return false;
  }

  if (isPreserved(c)) {
    return false;
  }

  const max = Math.max(c.r, c.g, c.b);
  const min = Math.min(c.r, c.g, c.b);
  const chroma = max - min;

  if (max > 46) {
    return false;
  }

  /*
   Targets what is still visible in the supplied screenshots:
   - neutral/warm near-black: #0d0d0d, #0e0e0e, #101010, #121211
   - warm brown/gold dark:    #131312, #16140d, similar values
   It deliberately excludes cool blue-neutral approved panels.
  */
  const nearGray = chroma <= 5;
  const warmDark =
    c.r >= c.g - 1 &&
    c.g >= c.b - 2 &&
    c.r - c.b >= 2;

  return nearGray || warmDark;
}

function isCandidate(el, headingRect) {
  if (!(el instanceof HTMLElement)) {
    return false;
  }

  if (SKIP_TAGS.has(el.tagName)) {
    return false;
  }

  if (el.closest("button,a,input,select,textarea")) {
    return false;
  }

  const rect = el.getBoundingClientRect();

  if (rect.width < 100 || rect.height < 28 || rect.width * rect.height < 1600) {
    return false;
  }

  /*
   Keep changes inside the page content region.
   This prevents REV29 from touching the sidebar or top navigation.
  */
  if (window.innerWidth >= 900) {
    const contentLeft = Math.max(175, headingRect.left - 35);

    if (rect.left < contentLeft) {
      return false;
    }
  }

  if (rect.top < headingRect.top - 80) {
    return false;
  }

  return true;
}

function neutralizeElement(el, style) {
  el.classList.add(REV29_CLASS);
  el.style.setProperty("background-color", "#0f141a", "important");
  el.style.setProperty("box-shadow", "none", "important");

  const borderVisible =
    parseFloat(style.borderTopWidth || "0") > 0 ||
    parseFloat(style.borderRightWidth || "0") > 0 ||
    parseFloat(style.borderBottomWidth || "0") > 0 ||
    parseFloat(style.borderLeftWidth || "0") > 0;

  if (borderVisible) {
    el.style.setProperty("border-color", "#27303a", "important");
  }
}

function applyRev29() {
  scheduled = false;

  const root = document.getElementById("root");
  if (!root) {
    return;
  }

  root.classList.remove(ROOT_GUEST, ROOT_MEDIA);

  const page = detectPage();
  if (!page) {
    return;
  }

  root.classList.add(page.kind === "guests" ? ROOT_GUEST : ROOT_MEDIA);

  const headingRect = page.heading.getBoundingClientRect();
  const nodes = root.querySelectorAll(
    "div,section,article,header,footer,aside,form,table,thead,tbody,tr,td,th,ul,li"
  );

  let count = 0;

  for (const el of nodes) {
    if (!isCandidate(el, headingRect)) {
      continue;
    }

    const style = getComputedStyle(el);

    /*
     Preserve actual media/background imagery.
     We only correct flat fill colours.
    */
    if (style.backgroundImage && style.backgroundImage !== "none") {
      continue;
    }

    const color = parseRgb(style.backgroundColor);

    if (!shouldNeutralize(color)) {
      continue;
    }

    neutralizeElement(el, style);
    count += 1;
  }

  const pageName = page.kind === "guests" ? "Guests" : "Media Manager";

  if (lastPage !== pageName || lastCount !== count) {
    console.info(`[StayQR REV29] ${pageName}: neutralized ${count} remaining warm/dark surface(s).`);
    lastPage = pageName;
    lastCount = count;
  }
}

function scheduleApply() {
  if (scheduled) {
    return;
  }

  scheduled = true;
  requestAnimationFrame(applyRev29);
}

function startRev29() {
  scheduleApply();

  setTimeout(scheduleApply, 100);
  setTimeout(scheduleApply, 400);
  setTimeout(scheduleApply, 1200);

  const root = document.getElementById("root");

  if (root) {
    const observer = new MutationObserver(scheduleApply);

    observer.observe(root, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "style", "aria-selected"],
    });
  }

  window.addEventListener("popstate", scheduleApply);
  window.addEventListener("hashchange", scheduleApply);
  window.addEventListener("resize", scheduleApply);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startRev29, { once: true });
} else {
  startRev29();
}
