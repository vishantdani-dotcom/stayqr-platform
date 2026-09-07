const ROOT = () => document.getElementById("root");
let queued = false;

function txt(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function lower(el) {
  return txt(el).toLowerCase();
}

function exactHeading(value) {
  const root = ROOT();
  if (!root) return null;

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll("h1,h2,h3")]
    .find((el) => lower(el) === wanted) || null;
}

function exactText(value, selector = "button,a,[role='button'],span,div") {
  const root = ROOT();
  if (!root) return null;

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted)
    .sort((a, b) => a.childElementCount - b.childElementCount)[0] || null;
}

function exactAll(value, selector = "button,a,[role='button']") {
  const root = ROOT();
  if (!root) return [];

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted);
}

function clickable(el) {
  if (!el) return null;

  if (el.matches("button,a,[role='button'],label")) {
    return el;
  }

  return el.closest("button,a,[role='button'],label") || el;
}

function clearClasses(el) {
  if (!el) return;

  el.classList.remove(
    "rev31-action-primary",
    "rev31-action-secondary",
    "rev31-action-chip",
    "rev31-action-disabled",
    "rev31-tab-control",
    "rev31-tab-active",
    "rev31-checkin-neutral-action"
  );
}

function activeSignal(el) {
  if (!el) return false;

  const nodes = [el, el.parentElement, el.parentElement?.parentElement].filter(Boolean);

  return nodes.some((node) => {
    const cls = String(node.className || "").toLowerCase();

    return (
      node.getAttribute?.("aria-selected") === "true" ||
      node.getAttribute?.("aria-current") === "page" ||
      node.getAttribute?.("aria-pressed") === "true" ||
      /\b(active|selected|current)\b/.test(cls)
    );
  });
}

function styleGuestConsent() {
  if (!exactHeading("Guests")) return false;
  if (!exactText("Guest contact preferences", "h2,h3,div,span")) return false;

  const refresh = clickable(exactText("Refresh", "button,a,[role='button'],span"));
  if (refresh && !refresh.disabled) {
    clearClasses(refresh);
    refresh.classList.add("rev31-action-primary");
  }

  for (const el0 of exactAll("Opt out")) {
    const el = clickable(el0);
    if (!el || el.disabled) continue;
    clearClasses(el);
    el.classList.add("rev31-action-secondary");
  }

  for (const label of ["Stay updates +", "Marketing +"]) {
    for (const el0 of exactAll(label)) {
      const el = clickable(el0);
      if (!el || el.disabled) continue;
      clearClasses(el);
      el.classList.add("rev31-action-chip");
    }
  }

  for (const el0 of exactAll("Open WhatsApp")) {
    const el = clickable(el0);
    if (!el) continue;

    clearClasses(el);

    if (el.disabled || el.getAttribute("aria-disabled") === "true") {
      el.classList.add("rev31-action-disabled");
    } else {
      el.classList.add("rev31-action-secondary");
    }
  }

  return true;
}

function findInvoiceTab(label) {
  const root = ROOT();
  if (!root) return null;

  const wanted = label.toLowerCase();

  const candidates = [...root.querySelectorAll(
    "button,a,[role='tab'],[role='button'],span,div"
  )].filter((el) => lower(el) === wanted);

  for (const candidate of candidates) {
    const hit = clickable(candidate);
    if (hit) return hit;
  }

  return null;
}

function styleInvoices() {
  if (!exactHeading("Invoice, Cashier & Night Audit")) return false;

  const labels = [
    "Invoices",
    "Receipts",
    "Cashier Shifts",
    "Night Audit",
    "GST / Tax Setup"
  ];

  const tabs = labels
    .map((label) => ({ label, el: findInvoiceTab(label) }))
    .filter((item) => item.el);

  if (!tabs.length) return false;

  for (const { el } of tabs) {
    clearClasses(el);
    el.classList.add("rev31-tab-control");

    if (activeSignal(el)) {
      el.classList.add("rev31-tab-active");
    }
  }

  /*
   Fallback for the current Invoices view seen in the supplied screenshot.
   The earlier global neutralization removed its gold fill but left the
   selected label dark. "Invoice register" uniquely identifies this tab body.
  */
  const invoiceRegister = exactText("Invoice register", "h2,h3,h4,div,span");

  if (invoiceRegister) {
    const invoiceTab = tabs.find((item) => item.label === "Invoices")?.el;
    if (invoiceTab) {
      invoiceTab.classList.add("rev31-tab-active");
    }
  }

  return true;
}

function styleOperationsCentre() {
  const heading =
    exactHeading("Operations Centre") ||
    exactText("Operations Centre", "h1,h2,h3,div,span");

  if (!heading) return false;

  const labels = [
    "Notifications",
    "Activity",
    "Preferences",
    "Templates",
    "Support",
    "Announcements",
    "Delivery",
    "Diagnostics",
    "System settings"
  ];

  const tabs = labels
    .map((label) => ({ label, el: findInvoiceTab(label) }))
    .filter((item) => item.el);

  for (const { el } of tabs) {
    clearClasses(el);
    el.classList.add("rev31-tab-control");

    if (activeSignal(el)) {
      el.classList.add("rev31-tab-active");
    }
  }

  /*
   Exact current screenshot: Preferences body.
   Force only the selected Preferences tab to the accepted dark-neutral state.
  */
  if (exactText("My Notification Preferences", "h1,h2,h3,div,span")) {
    const pref = tabs.find((item) => item.label === "Preferences")?.el;

    if (pref) {
      pref.classList.add("rev31-tab-active");
    }
  }

  return true;
}

function parseRgb(value) {
  const m = String(value || "").match(
    /rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)/i
  );

  if (!m) return null;

  return {
    r: Number(m[1]),
    g: Number(m[2]),
    b: Number(m[3]),
    a: m[4] == null ? 1 : Number(m[4])
  };
}

function warmDark(el) {
  const style = getComputedStyle(el);
  const c = parseRgb(style.backgroundColor);

  if (!c || c.a < .05) return false;

  const max = Math.max(c.r, c.g, c.b);
  const min = Math.min(c.r, c.g, c.b);

  const warm =
    c.r >= c.g - 1 &&
    c.g >= c.b - 2 &&
    c.r - c.b >= 3;

  return max < 85 && warm && (max - min) >= 3;
}

function findScanIdAction() {
  const root = ROOT();
  if (!root) return null;

  const scanText = exactText("Scan ID", "button,a,[role='button'],label,div,span,strong");
  if (!scanText) return null;

  const direct = clickable(scanText);

  if (
    direct &&
    direct.getBoundingClientRect().width >= 180 &&
    direct.getBoundingClientRect().height >= 60
  ) {
    return direct;
  }

  let current = scanText;

  for (let i = 0; current && i < 8; i += 1) {
    if (current instanceof HTMLElement) {
      const rect = current.getBoundingClientRect();
      const body = lower(current);

      if (
        rect.width >= 220 &&
        rect.height >= 70 &&
        rect.height <= 180 &&
        body.includes("scan id") &&
        body.includes("use camera")
      ) {
        return current;
      }
    }

    current = current.parentElement;
  }

  return direct;
}

function styleCheckInOut() {
  if (!exactHeading("Guest Check-in")) return false;

  const scan = findScanIdAction();

  if (scan) {
    clearClasses(scan);
    scan.classList.add("rev31-checkin-neutral-action");
  }

  /*
   Catch only additional warm-dark INTERACTIVE controls on this page.
   Bright approved gold primary CTAs are intentionally excluded.
  */
  const root = ROOT();

  for (const el of root.querySelectorAll("button,[role='button'],label")) {
    if (!(el instanceof HTMLElement)) continue;
    if (el.disabled || el.getAttribute("aria-disabled") === "true") continue;

    const text = lower(el);

    if (
      text.includes("complete check-in") ||
      text === "check in" ||
      text.includes("save &")
    ) {
      continue;
    }

    if (warmDark(el)) {
      clearClasses(el);
      el.classList.add("rev31-checkin-neutral-action");
    }
  }

  return true;
}

function applyRev31() {
  queued = false;

  styleGuestConsent();
  styleInvoices();
  styleOperationsCentre();
  styleCheckInOut();
}

function scheduleRev31() {
  if (queued) return;

  queued = true;
  requestAnimationFrame(applyRev31);
}

function bootRev31() {
  scheduleRev31();

  setTimeout(scheduleRev31, 100);
  setTimeout(scheduleRev31, 350);
  setTimeout(scheduleRev31, 900);
  setTimeout(scheduleRev31, 1800);

  const root = ROOT();

  if (root) {
    const observer = new MutationObserver(scheduleRev31);

    observer.observe(root, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "style", "aria-selected", "aria-current", "aria-pressed", "disabled"]
    });
  }

  window.addEventListener("popstate", scheduleRev31);
  window.addEventListener("hashchange", scheduleRev31);
  window.addEventListener("resize", scheduleRev31);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev31, { once: true });
} else {
  bootRev31();
}
