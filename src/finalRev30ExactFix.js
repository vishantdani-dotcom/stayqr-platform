const EXACT_CLASS = "rev30-exact-neutral";
const GUEST_ROOT_CLASS = "rev30-guests";
const MEDIA_ROOT_CLASS = "rev30-media";

let queued = false;
let lastSignature = "";

function textOf(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function exactHeading(root, value) {
  const wanted = value.toLowerCase();

  return [...root.querySelectorAll("h1,h2,h3")]
    .find((el) => textOf(el).toLowerCase() === wanted) || null;
}

function findByText(root, needle) {
  const wanted = needle.toLowerCase();

  const candidates = [...root.querySelectorAll(
    "h1,h2,h3,h4,p,span,strong,small,div,label"
  )]
    .filter((el) => textOf(el).toLowerCase().includes(wanted))
    .sort((a, b) => textOf(a).length - textOf(b).length);

  return candidates[0] || null;
}

function findButton(root, label) {
  const wanted = label.toLowerCase();

  return [...root.querySelectorAll("button,a")]
    .find((el) => textOf(el).toLowerCase() === wanted) || null;
}

function ancestorChain(el) {
  const result = [];
  let current = el;

  while (current && current instanceof HTMLElement) {
    result.push(current);
    current = current.parentElement;
  }

  return result;
}

function lowestCommonAncestor(elements) {
  const valid = elements.filter(Boolean);

  if (!valid.length) {
    return null;
  }

  const firstChain = ancestorChain(valid[0]);

  for (const candidate of firstChain) {
    if (valid.every((el) => candidate.contains(el))) {
      return candidate;
    }
  }

  return null;
}

function climb(el, predicate, maxDepth = 10) {
  let current = el;

  for (let depth = 0; current && depth <= maxDepth; depth += 1) {
    if (current instanceof HTMLElement && predicate(current)) {
      return current;
    }

    current = current.parentElement;
  }

  return null;
}

function mark(el, targetName) {
  if (!(el instanceof HTMLElement)) {
    return false;
  }

  /*
   Safety: never turn a media element, input or button into a panel.
  */
  if (el.matches("img,video,picture,canvas,svg,button,a,input,select,textarea")) {
    return false;
  }

  el.classList.add(EXACT_CLASS);
  el.dataset.rev30Target = targetName;

  /*
   Inline !important intentionally beats legacy inline gradients/shorthands.
   These exact containers contain no image backgrounds.
  */
  el.style.setProperty("background", "#0f141a", "important");
  el.style.setProperty("background-color", "#0f141a", "important");
  el.style.setProperty("background-image", "none", "important");
  el.style.setProperty("border-color", "#27303a", "important");
  el.style.setProperty("box-shadow", "none", "important");

  return true;
}

function guestPage(root) {
  const heading = exactHeading(root, "Guests");
  return heading ? { heading } : null;
}

function mediaPage(root) {
  const heading = exactHeading(root, "Media Manager");
  return heading ? { heading } : null;
}

function fixGuestDirectory(root) {
  const title = findByText(root, "Guest profiles and stay history");
  const search = root.querySelector(
    'input[placeholder*="Search name"], input[placeholder*="phone, email, ID"]'
  );
  const exportButton = findButton(root, "Controlled export");
  const refreshButton = findButton(root, "Refresh directory");

  let panel = lowestCommonAncestor([
    title,
    search,
    exportButton || refreshButton
  ]);

  /*
   The LCA should be the hero card. If markup nests controls one level deeper,
   climb only until it contains the title + search + at least one action.
  */
  if (panel && panel.getBoundingClientRect().width > window.innerWidth * 0.92) {
    panel = climb(title, (el) =>
      el.contains(search) &&
      (el.contains(exportButton) || el.contains(refreshButton)) &&
      el.getBoundingClientRect().height < 220
    );
  }

  return mark(panel, "guest-directory-hero");
}

function fixGuestConsentBanner(root) {
  const title = findByText(root, "Automated WhatsApp campaigns");
  const description = findByText(
    root,
    "Bulk/template automation is intentionally on hold for launch"
  );

  let panel = lowestCommonAncestor([title, description]);

  if (panel) {
    panel = climb(title, (el) =>
      el.contains(description) &&
      el.getBoundingClientRect().height >= 35 &&
      el.getBoundingClientRect().height <= 120 &&
      el.getBoundingClientRect().width >= 300
    ) || panel;
  }

  return mark(panel, "guest-consent-upcoming-banner");
}

function fixGuestConsentTable(root) {
  const search = root.querySelector(
    'input[placeholder*="Search guest, phone or room"]'
  );

  if (!search) {
    return false;
  }

  const allGuests = [...root.querySelectorAll("select")]
    .find((el) => textOf(el).toLowerCase().includes("all guests"));

  const openWhatsapp = findButton(root, "Open WhatsApp");

  let panel = lowestCommonAncestor([
    search,
    allGuests,
    openWhatsapp
  ]);

  if (!panel || panel.getBoundingClientRect().height > 500) {
    panel = climb(search, (el) =>
      el.querySelector("table,tbody") &&
      el.getBoundingClientRect().width >= 500 &&
      el.getBoundingClientRect().height >= 120
    );
  }

  return mark(panel, "guest-consent-table");
}

function fixMediaUploadPanel(root) {
  const uploadButton =
    findButton(root, "Upload image / short video") ||
    findByText(root, "Upload image / short video");

  if (!uploadButton) {
    return false;
  }

  const panel = climb(uploadButton, (el) => {
    const selects = el.querySelectorAll("select").length;
    const fields = el.querySelectorAll("input,textarea").length;
    const hasCategory = textOf(el).toLowerCase().includes("category");
    const hasScope = textOf(el).toLowerCase().includes("scope");

    const rect = el.getBoundingClientRect();

    return (
      selects >= 2 &&
      fields >= 2 &&
      hasCategory &&
      hasScope &&
      rect.height >= 120 &&
      rect.height <= 300 &&
      rect.width >= 500
    );
  }, 12);

  return mark(panel, "media-upload-panel");
}

function fixMediaLibraryPanel(root) {
  const search = root.querySelector('input[placeholder*="Search media"]');

  if (!search) {
    return false;
  }

  const removeButton = [...root.querySelectorAll("button")]
    .find((el) => textOf(el).toLowerCase() === "remove");

  const panel = climb(search, (el) => {
    const rect = el.getBoundingClientRect();
    const hasMedia = !!el.querySelector("img,video");
    const hasRemove = !!removeButton && el.contains(removeButton);

    return (
      hasMedia &&
      hasRemove &&
      rect.width >= 600 &&
      rect.height >= 180
    );
  }, 12);

  return mark(panel, "media-library-panel");
}

function applyExactFix() {
  queued = false;

  const root = document.getElementById("root");

  if (!root) {
    return;
  }

  root.classList.remove(GUEST_ROOT_CLASS, MEDIA_ROOT_CLASS);

  const results = [];

  if (guestPage(root)) {
    root.classList.add(GUEST_ROOT_CLASS);

    results.push(["guest-directory-hero", fixGuestDirectory(root)]);
    results.push(["guest-consent-banner", fixGuestConsentBanner(root)]);
    results.push(["guest-consent-table", fixGuestConsentTable(root)]);
  } else if (mediaPage(root)) {
    root.classList.add(MEDIA_ROOT_CLASS);

    results.push(["media-upload-panel", fixMediaUploadPanel(root)]);
    results.push(["media-library-panel", fixMediaLibraryPanel(root)]);
  } else {
    return;
  }

  const signature = results
    .map(([name, ok]) => `${name}:${ok ? "PASS" : "N/A"}`)
    .join("|");

  if (signature !== lastSignature) {
    console.info("[StayQR REV30 EXACT]", signature);
    lastSignature = signature;
  }
}

function scheduleExactFix() {
  if (queued) {
    return;
  }

  queued = true;
  requestAnimationFrame(applyExactFix);
}

function boot() {
  scheduleExactFix();

  setTimeout(scheduleExactFix, 100);
  setTimeout(scheduleExactFix, 350);
  setTimeout(scheduleExactFix, 900);
  setTimeout(scheduleExactFix, 1800);

  const root = document.getElementById("root");

  if (root) {
    const observer = new MutationObserver(scheduleExactFix);

    observer.observe(root, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["class", "style", "aria-selected"],
    });
  }

  window.addEventListener("popstate", scheduleExactFix);
  window.addEventListener("hashchange", scheduleExactFix);
  window.addEventListener("resize", scheduleExactFix);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}
