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

function climb(el, predicate, maxDepth = 12) {
  let current = el;

  for (let depth = 0; current && depth <= maxDepth; depth += 1) {
    if (current instanceof HTMLElement && predicate(current)) {
      return current;
    }
    current = current.parentElement;
  }

  return null;
}

function ensureLoginMotion() {
  const login = document.querySelector(".sq-login-page");
  const mobileViewport = window.matchMedia?.("(max-width: 900px)")?.matches ?? window.innerWidth <= 900;

  if (!login || !mobileViewport) {
    document.querySelectorAll(".sq35-login-motion").forEach((el) => el.remove());
    return false;
  }

  login.classList.add("sq35-login-mobile-motion-ready");

  if (login.querySelector(":scope > .sq35-login-motion")) {
    return true;
  }

  const motion = document.createElement("div");
  motion.className = "sq35-login-motion";
  motion.setAttribute("aria-hidden", "true");

  motion.innerHTML = `
    <div class="sq35-grid"></div>
    <div class="sq35-glow sq35-glow-a"></div>
    <div class="sq35-glow sq35-glow-b"></div>
    <div class="sq35-scene sq35-scene-top">
      <div class="sq35-orbit sq35-orbit-a"></div>
      <div class="sq35-orbit sq35-orbit-b"></div>
      <div class="sq35-orb"></div>
      <div class="sq35-qr">
        <i></i><i></i><i></i><i></i>
      </div>
    </div>
    <div class="sq35-scene sq35-scene-bottom">
      <div class="sq35-keycard">
        <span>STAYQR</span>
        <b>HOTEL STAFF</b>
        <small>Secure staff access</small>
      </div>
    </div>
    <div class="sq35-scanline"></div>
  `;

  login.appendChild(motion);
  return true;
}

function styleSetupSummary() {
  const marker = exactText("Setup summary", "h1,h2,h3,h4,div,span");

  if (!marker) {
    document.querySelectorAll(".rev35-setup-summary,.rev35-setup-stat")
      .forEach((el) => el.classList.remove("rev35-setup-summary", "rev35-setup-stat"));
    return false;
  }

  const summary = climb(marker, (el) => {
    const body = lower(el);
    const rect = el.getBoundingClientRect();

    const signals = [
      "languages enabled",
      "contact links configured",
      "local convenience links configured",
      "photos available",
      "room instructions"
    ];

    const signalCount = signals.filter((signal) => body.includes(signal)).length;

    return (
      signalCount >= 3 &&
      rect.width >= 220 &&
      rect.height >= 120
    );
  });

  if (!summary) return false;

  summary.classList.add("rev35-setup-summary");

  const statSignals = [
    "languages enabled",
    "contact links configured",
    "local convenience links configured",
    "photos available",
    "room instructions"
  ];

  for (const signal of statSignals) {
    const candidates = [...summary.querySelectorAll("div,section,article")]
      .filter((el) => lower(el).includes(signal))
      .sort((a, b) => {
        const ar = a.getBoundingClientRect();
        const br = b.getBoundingClientRect();
        return ar.width * ar.height - br.width * br.height;
      });

    for (const candidate of candidates) {
      const rect = candidate.getBoundingClientRect();
      const body = lower(candidate);

      if (
        rect.width >= 120 &&
        rect.height >= 56 &&
        rect.height <= 150 &&
        body.includes(signal)
      ) {
        candidate.classList.add("rev35-setup-stat");
        break;
      }
    }
  }

  return true;
}

function applyRev35() {
  queued = false;
  ensureLoginMotion();
  styleSetupSummary();
}

function scheduleRev35() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(applyRev35);
}

function bootRev35() {
  scheduleRev35();

  setTimeout(scheduleRev35, 100);
  setTimeout(scheduleRev35, 350);
  setTimeout(scheduleRev35, 900);
  setTimeout(scheduleRev35, 1800);

  const root = ROOT();

  if (root) {
    const observer = new MutationObserver(scheduleRev35);

    observer.observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("popstate", scheduleRev35);
  window.addEventListener("hashchange", scheduleRev35);
  window.addEventListener("resize", scheduleRev35);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev35, { once: true });
} else {
  bootRev35();
}

