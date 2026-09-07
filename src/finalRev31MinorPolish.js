const ROOT = () => document.getElementById("root");
let queued = false;

const TAB = "rev32-tab-control";
const TAB_ACTIVE = "rev32-tab-active";
const NEUTRAL = "rev32-neutral-card";
const PRIMARY = "rev32-primary-action";
const SECONDARY = "rev32-secondary-action";
const CHIP = "rev32-chip-action";

function txt(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function lower(el) {
  return txt(el).toLowerCase();
}

function exactText(value, selector = "button,a,[role='button'],[role='tab'],h1,h2,h3,h4,p,span,div,label") {
  const root = ROOT();
  if (!root) return null;

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted)
    .sort((a, b) => a.childElementCount - b.childElementCount)[0] || null;
}

function allExact(value, selector = "button,a,[role='button'],[role='tab'],span,div,label") {
  const root = ROOT();
  if (!root) return [];

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted);
}

function clickable(el) {
  if (!el) return null;

  if (el.matches("button,a,[role='button'],[role='tab'],label")) {
    return el;
  }

  return el.closest("button,a,[role='button'],[role='tab'],label") || el;
}

function setOnly(el, classes) {
  if (!el) return;

  for (const cls of [
    "rev31-action-primary",
    "rev31-action-secondary",
    "rev31-action-chip",
    "rev31-action-disabled",
    "rev31-tab-control",
    "rev31-tab-active",
    "rev31-checkin-neutral-action",
    TAB,
    TAB_ACTIVE,
    NEUTRAL,
    PRIMARY,
    SECONDARY,
    CHIP
  ]) {
    if (!classes.includes(cls)) {
      el.classList.remove(cls);
    }
  }

  for (const cls of classes) {
    el.classList.add(cls);
  }
}

function nativeActive(el) {
  if (!el) return false;

  const nodes = [el, el.parentElement, el.parentElement?.parentElement].filter(Boolean);

  return nodes.some((node) => {
    const raw = String(node.className || "")
      .split(/\s+/)
      .filter((c) => c && !c.startsWith("rev31") && !c.startsWith("rev32"))
      .join(" ")
      .toLowerCase();

    return (
      node.getAttribute?.("aria-selected") === "true" ||
      node.getAttribute?.("aria-current") === "page" ||
      node.getAttribute?.("aria-pressed") === "true" ||
      node.getAttribute?.("data-state") === "active" ||
      /\b(active|selected|current)\b/.test(raw)
    );
  });
}

function exactDescendant(container, label) {
  const wanted = label.toLowerCase();

  return [...container.querySelectorAll("button,a,[role='tab'],[role='button'],span,div")]
    .find((el) => lower(el) === wanted) || null;
}

function findTabRow(labels) {
  const root = ROOT();
  if (!root) return null;

  const candidates = [...root.querySelectorAll("nav,div,section,header")].filter((el) => {
    const rect = el.getBoundingClientRect();

    if (rect.width < 420 || rect.height < 28 || rect.height > 95) {
      return false;
    }

    return labels.every((label) => !!exactDescendant(el, label));
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return candidates[0] || null;
}

function styleTabRow(labels, activeFallback = null) {
  const row = findTabRow(labels);
  if (!row) return false;

  for (const label of labels) {
    const raw = exactDescendant(row, label);
    const control = clickable(raw);
    if (!control) continue;

    const active = nativeActive(control) || label === activeFallback;
    setOnly(control, active ? [TAB, TAB_ACTIVE] : [TAB]);

    for (const child of control.querySelectorAll("*")) {
      child.classList.toggle("rev32-tab-label-active", active);
      child.classList.toggle("rev32-tab-label", !active);
    }
  }

  return true;
}

function climb(el, predicate, maxDepth = 10) {
  let current = el;

  for (let i = 0; current && i <= maxDepth; i += 1) {
    if (current instanceof HTMLElement && predicate(current)) {
      return current;
    }
    current = current.parentElement;
  }

  return null;
}

function markNeutral(el) {
  if (!el || !(el instanceof HTMLElement)) return false;
  el.classList.add(NEUTRAL);
  return true;
}

function styleGuestConsent() {
  const guestTitle = exactText("Guests", "h1,h2,h3");
  const contactTitle = exactText("Guest contact preferences", "h1,h2,h3,div,span");

  if (!guestTitle || !contactTitle) return false;

  styleTabRow(["Active stays", "Guest directory & history", "Contact & consent"], "Contact & consent");

  const refresh = clickable(exactText("Refresh", "button,a,[role='button'],span"));
  if (refresh && !refresh.disabled) {
    setOnly(refresh, [PRIMARY]);
  }

  for (const raw of allExact("Opt out", "button,a,[role='button'],span")) {
    const el = clickable(raw);
    if (el && !el.disabled) {
      setOnly(el, [SECONDARY]);
    }
  }

  for (const label of ["Stay updates +", "Marketing +"]) {
    for (const raw of allExact(label, "button,a,[role='button'],span")) {
      const el = clickable(raw);
      if (el && !el.disabled) {
        setOnly(el, [CHIP]);
      }
    }
  }

  return true;
}

function styleInvoices() {
  const heading = exactText("Invoice, Cashier & Night Audit", "h1,h2,h3");
  if (!heading) return false;

  const root = ROOT();

  // Remove REV31 tab styling from any accidental KPI labels such as "Receipts".
  for (const el of root.querySelectorAll(".rev31-tab-control,.rev31-tab-active")) {
    el.classList.remove("rev31-tab-control", "rev31-tab-active");
  }

  const labels = ["Invoices", "Receipts", "Cashier Shifts", "Night Audit", "GST / Tax Setup"];

  let fallback = null;
  if (exactText("Invoice register", "h1,h2,h3,h4,div,span")) fallback = "Invoices";
  else if (exactText("Receipt register", "h1,h2,h3,h4,div,span")) fallback = "Receipts";

  styleTabRow(labels, fallback);

  return true;
}

function styleOperationsCentre() {
  const breadcrumb = exactText("Operations Centre", "h1,h2,h3,div,span");
  const preferenceBody = exactText("My Notification Preferences", "h1,h2,h3,div,span");
  const systemSave = exactText("Save system settings", "button,a,[role='button'],span");

  if (!breadcrumb && !preferenceBody && !systemSave) return false;

  let fallback = null;
  if (preferenceBody) fallback = "Preferences";
  if (systemSave) fallback = "System settings";

  styleTabRow(
    ["Notifications", "Activity", "Preferences", "Templates", "Support", "Announcements", "Delivery", "Diagnostics", "System settings"],
    fallback
  );

  // Notification preference cards.
  for (const label of ["In-app notifications", "Email notifications", "Manual WhatsApp"]) {
    const textEl = exactText(label, "label,span,div,strong");
    if (!textEl) continue;

    const card = climb(textEl, (el) => {
      const rect = el.getBoundingClientRect();
      return !!el.querySelector('input[type="checkbox"]') && rect.width >= 180 && rect.height >= 45 && rect.height <= 110;
    });

    markNeutral(card);
  }

  // System Settings warm "Prices include tax" card.
  const prices = exactText("Prices include tax", "label,span,div,strong");
  if (prices) {
    const card = climb(prices, (el) => {
      const rect = el.getBoundingClientRect();
      return !!el.querySelector('input[type="checkbox"]') && rect.width >= 180 && rect.height >= 45 && rect.height <= 110;
    });
    markNeutral(card);
  }

  return true;
}

function styleCheckInOut() {
  const heading = exactText("Guest Check-in", "h1,h2,h3");
  if (!heading) return false;

  const primaryText = exactText("Enter primary guest name above", "div,span,p,strong");
  if (primaryText) {
    const card = climb(primaryText, (el) => {
      const body = lower(el);
      const rect = el.getBoundingClientRect();

      return (
        body.includes("primary guest") &&
        body.includes("enter primary guest name above") &&
        rect.width >= 360 &&
        rect.height >= 45 &&
        rect.height <= 120
      );
    });
    markNeutral(card);
  }

  const addGuest = clickable(exactText("Add another guest", "button,a,[role='button'],span,div"));
  if (addGuest) {
    setOnly(addGuest, [SECONDARY]);
  }

  return true;
}

function styleGuestGuideBuilder() {
  const guideSections = exactText("Guide sections", "h1,h2,h3,h4,div,span");
  if (!guideSections) return false;

  const root = ROOT();

  for (const checkbox of root.querySelectorAll('input[type="checkbox"]:not([role="switch"])')) {
    const row = climb(checkbox, (el) => {
      const rect = el.getBoundingClientRect();
      const save = [...el.querySelectorAll("button,a,[role='button']")]
        .some((b) => lower(b) === "save");

      return save && rect.width >= 520 && rect.height >= 45 && rect.height <= 110;
    });

    markNeutral(row);
  }

  return true;
}

function styleHotelSetup() {
  const stillRequired = exactText("Still required", "h1,h2,h3,h4,div,span");
  if (!stillRequired) return false;

  const panel = climb(stillRequired, (el) => {
    const rect = el.getBoundingClientRect();
    const body = lower(el);

    return body.includes("still required") && body.includes("subscription") &&
      rect.width >= 420 && rect.height >= 55 && rect.height <= 150;
  });

  markNeutral(panel);
  return true;
}

function setCheckboxScope() {
  const root = ROOT();
  if (!root) return;

  const shouldUseGoldCheckboxes =
    !!exactText("Guide sections", "h1,h2,h3,h4,div,span") ||
    !!exactText("My Notification Preferences", "h1,h2,h3,div,span") ||
    !!exactText("Save system settings", "button,a,[role='button'],span");

  root.classList.toggle("rev32-gold-checkbox-scope", shouldUseGoldCheckboxes);
}

function applyRev32() {
  queued = false;

  setCheckboxScope();
  styleGuestConsent();
  styleInvoices();
  styleOperationsCentre();
  styleCheckInOut();
  styleGuestGuideBuilder();
  styleHotelSetup();
}

function scheduleRev32() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(applyRev32);
}

function bootRev32() {
  scheduleRev32();

  setTimeout(scheduleRev32, 120);
  setTimeout(scheduleRev32, 450);
  setTimeout(scheduleRev32, 1000);
  setTimeout(scheduleRev32, 1800);

  const root = ROOT();

  if (root) {
    const observer = new MutationObserver(scheduleRev32);

    observer.observe(root, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "aria-selected", "aria-current", "aria-pressed", "data-state", "disabled"]
    });
  }

  window.addEventListener("popstate", scheduleRev32);
  window.addEventListener("hashchange", scheduleRev32);
  window.addEventListener("resize", scheduleRev32);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev32, { once: true });
} else {
  bootRev32();
}

