const ROOT = () => document.getElementById("root");
let queued = false;

function textOf(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function lower(el) {
  return textOf(el).toLowerCase();
}

function exactText(value, selector = "h1,h2,h3,h4,p,span,div,label,button,a,[role='button']") {
  const root = ROOT();
  if (!root) return null;

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted)
    .sort((a, b) => a.childElementCount - b.childElementCount)[0] || null;
}

function includesText(value, selector = "h1,h2,h3,h4,p,span,div,label") {
  const root = ROOT();
  if (!root) return null;

  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el).includes(wanted))
    .sort((a, b) => textOf(a).length - textOf(b).length)[0] || null;
}

function clickable(el) {
  if (!el) return null;
  if (el.matches("button,a,[role='button'],label")) return el;
  return el.closest("button,a,[role='button'],label") || el;
}

function climb(el, predicate, maxDepth = 12) {
  let current = el;

  for (let i = 0; current && i <= maxDepth; i += 1) {
    if (current instanceof HTMLElement && predicate(current)) {
      return current;
    }
    current = current.parentElement;
  }

  return null;
}

function mark(el, cls) {
  if (!(el instanceof HTMLElement)) return false;
  el.classList.add(cls);
  return true;
}

function setPageClass(name, on) {
  const root = ROOT();
  if (!root) return;
  root.classList.toggle(name, !!on);
}

function styleContactConsent() {
  const guestHeading = exactText("Guests", "h1,h2,h3");
  const contactHeading = exactText("Guest contact preferences", "h1,h2,h3,div,span");

  const active = !!guestHeading && !!contactHeading;
  setPageClass("rev34-contact-consent", active);

  if (!active) return false;

  const bannerText = includesText("Automated WhatsApp campaigns", "h1,h2,h3,h4,p,span,div,strong");

  if (bannerText) {
    const banner = climb(bannerText, (el) => {
      const rect = el.getBoundingClientRect();
      const body = lower(el);

      return (
        body.includes("automated whatsapp campaigns") &&
        body.includes("bulk/template automation") &&
        rect.width >= 220 &&
        rect.height >= 42 &&
        rect.height <= 150
      );
    });

    mark(banner, "rev34-neutral-panel");
  }

  const search = document.querySelector('input[placeholder*="Search guest, phone or room"]');
  if (search) {
    const tableWrap = climb(search, (el) => {
      const rect = el.getBoundingClientRect();
      return (
        !!el.querySelector("table,tbody") &&
        rect.width >= 240 &&
        rect.height >= 120
      );
    });
    mark(tableWrap, "rev34-mobile-table-wrap");
  }

  return true;
}

function styleLanguages() {
  const marker = exactText("Languages shown to guests", "h1,h2,h3,h4,div,span");
  const active = !!marker;
  setPageClass("rev34-languages", active);

  if (!active) return false;

  const saveButton = exactText("Save enabled languages", "button,a,[role='button'],span,div");
  let section = null;

  if (saveButton) {
    section = climb(marker, (el) => {
      const checkCount = el.querySelectorAll('input[type="checkbox"],[role="checkbox"]').length;
      return (
        checkCount >= 3 &&
        el.contains(saveButton) &&
        el.getBoundingClientRect().width >= 220
      );
    });
  }

  if (!section) {
    section = climb(marker, (el) => el.querySelectorAll('input[type="checkbox"],[role="checkbox"]').length >= 3);
  }

  if (!section) return false;

  mark(section, "rev34-language-section");

  for (const control of section.querySelectorAll('input[type="checkbox"],[role="checkbox"]')) {
    const card = climb(control, (el) => {
      const rect = el.getBoundingClientRect();
      const body = textOf(el);

      return (
        rect.width >= 120 &&
        rect.height >= 44 &&
        rect.height <= 110 &&
        body.length <= 90
      );
    }, 7);

    mark(card, "rev34-language-card");
  }

  return true;
}

function styleReviewPublish() {
  const guideMarker = exactText("Guide sections", "h1,h2,h3,h4,div,span");
  const publishMarker = exactText("Publish guest guide", "h1,h2,h3,h4,div,span,button,a");

  const active = !!guideMarker || !!publishMarker;
  setPageClass("rev34-review-publish", active);

  if (!active) return false;

  if (guideMarker) {
    const guideSection = climb(guideMarker, (el) => {
      const saveCount = [...el.querySelectorAll("button,a,[role='button']")]
        .filter((b) => lower(b) === "save").length;

      const checkCount = el.querySelectorAll('input[type="checkbox"],[role="checkbox"]').length;

      return saveCount >= 2 && checkCount >= 2;
    });

    if (guideSection) {
      mark(guideSection, "rev34-guide-section");

      for (const control of guideSection.querySelectorAll('input[type="checkbox"],[role="checkbox"]')) {
        const row = climb(control, (el) => {
          const rect = el.getBoundingClientRect();
          const hasSave = [...el.querySelectorAll("button,a,[role='button']")]
            .some((b) => lower(b) === "save");

          return hasSave && rect.width >= 220 && rect.height >= 70 && rect.height <= 260;
        }, 8);

        if (row) {
          mark(row, "rev34-guide-row");

          for (const raw of row.querySelectorAll("button,a,[role='button']")) {
            if (lower(raw) === "save") {
              mark(clickable(raw), "rev34-secondary-action");
            }
          }
        }
      }
    }
  }

  if (publishMarker) {
    const panel = climb(publishMarker, (el) => {
      const rect = el.getBoundingClientRect();
      const body = lower(el);

      return (
        body.includes("publish guest guide") &&
        body.includes("version") &&
        rect.width >= 220 &&
        rect.height >= 100 &&
        rect.height <= 420
      );
    });

    mark(panel, "rev34-neutral-panel");
  }

  return true;
}

function styleServiceCatalogue() {
  const marker = exactText("Dynamic service catalogue", "h1,h2,h3,h4,div,span");
  const active = !!marker;
  setPageClass("rev34-service-catalogue", active);

  if (!active) return false;

  const panel = climb(marker, (el) => {
    const rect = el.getBoundingClientRect();
    const saveCount = [...el.querySelectorAll("button,a,[role='button']")]
      .filter((b) => lower(b) === "save category").length;

    return (
      saveCount >= 1 &&
      el.querySelectorAll("select,input").length >= 3 &&
      rect.width >= 220
    );
  });

  if (!panel) return false;

  mark(panel, "rev34-catalogue-panel");

  for (const saveRaw of [...panel.querySelectorAll("button,a,[role='button']")]
    .filter((b) => lower(b) === "save category")) {

    const save = clickable(saveRaw);
    const card = climb(save, (el) => {
      const rect = el.getBoundingClientRect();
      const hasSelect = !!el.querySelector("select");
      const hasNumber = !!el.querySelector('input[type="number"],input[inputmode="numeric"]');
      return hasSelect && rect.width >= 200 && rect.height >= 180 && rect.height <= 620 && (hasNumber || el.querySelectorAll("input").length >= 2);
    }, 10);

    if (card) {
      mark(card, "rev34-catalogue-card");
      mark(save, "rev34-primary-action");
    }
  }

  return true;
}

function styleRoleCheckboxes() {
  const root = ROOT();
  if (!root) return;

  for (const el of root.querySelectorAll('[role="checkbox"]')) {
    el.classList.add("rev34-role-checkbox");
  }
}

function applyRev34() {
  queued = false;

  styleContactConsent();
  styleLanguages();
  styleReviewPublish();
  styleServiceCatalogue();
  styleRoleCheckboxes();
}

function scheduleRev34() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(applyRev34);
}

function bootRev34() {
  scheduleRev34();

  setTimeout(scheduleRev34, 100);
  setTimeout(scheduleRev34, 350);
  setTimeout(scheduleRev34, 900);
  setTimeout(scheduleRev34, 1800);

  const root = ROOT();

  if (root) {
    const observer = new MutationObserver(scheduleRev34);

    observer.observe(root, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "style", "aria-checked", "aria-selected", "disabled"]
    });
  }

  window.addEventListener("popstate", scheduleRev34);
  window.addEventListener("hashchange", scheduleRev34);
  window.addEventListener("resize", scheduleRev34);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev34, { once: true });
} else {
  bootRev34();
}

