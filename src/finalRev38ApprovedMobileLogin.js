let rev38Queued = false;

function textOf(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function lower(el) {
  return textOf(el).toLowerCase();
}

function exactText(root, value, selector = "h1,h2,h3,h4,p,span,div,label,button,a,[role='button']") {
  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el) === wanted)
    .sort((a, b) => a.childElementCount - b.childElementCount)[0] || null;
}

function includesText(root, value, selector = "h1,h2,h3,h4,p,span,div,label") {
  const wanted = value.toLowerCase();

  return [...root.querySelectorAll(selector)]
    .filter((el) => lower(el).includes(wanted))
    .sort((a, b) => textOf(a).length - textOf(b).length)[0] || null;
}

function findAuthPanel(page) {
  const candidates = [...page.querySelectorAll("section,aside,div")].filter((el) => {
    const body = lower(el);
    return (
      body.includes("email address") &&
      body.includes("password") &&
      body.includes("sign in securely") &&
      body.includes("create owner account")
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return candidates[0] || null;
}

function buildHero() {
  const hero = document.createElement("section");
  hero.className = "sq37-mobile-desktop-hero sq37-generated-hero sq38-approved-hero";
  hero.setAttribute("aria-label", "StayQR platform overview");

  hero.innerHTML = `
    <div class="sq37-motion" aria-hidden="true">
      <span class="sq37-wave sq37-wave-a"></span>
      <span class="sq37-wave sq37-wave-b"></span>
      <span class="sq37-wave sq37-wave-c"></span>
      <span class="sq37-orbit sq37-orbit-a"></span>
      <span class="sq37-orbit sq37-orbit-b"></span>
      <span class="sq37-orbit-dot"></span>
      <span class="sq37-glow"></span>
    </div>

    <div class="sq37-hero-content">
      <div class="sq37-brand">
        <div class="sq37-brand-mark">SQ</div>
        <div>
          <strong>StayQR</strong>
          <small>Simplifying Checkinn</small>
        </div>
      </div>

      <div class="sq37-eyebrow">HOTEL OPERATIONS • GUEST EXPERIENCE</div>

      <h1>One workspace for the stay, from arrival to checkout.</h1>

      <p class="sq37-lead">
        Front desk operations, guest identity, room QR guides, service workflows
        and stay billing — connected in one secure hotel workspace.
      </p>

      <div class="sq37-feature-grid">
        <article class="sq37-feature">
          <span class="sq37-feature-icon">▦</span>
          <div>
            <strong>QR-first guest experience</strong>
            <p>Personalised room access during the active stay.</p>
          </div>
        </article>

        <article class="sq37-feature">
          <span class="sq37-feature-icon">◈</span>
          <div>
            <strong>Secure hotel access</strong>
            <p>Role-aware staff and platform authentication.</p>
          </div>
        </article>

        <article class="sq37-feature">
          <span class="sq37-feature-icon">ϟ</span>
          <div>
            <strong>Operational clarity</strong>
            <p>Check-in, service, billing and room status in one place.</p>
          </div>
        </article>
      </div>
    </div>
  `;

  return hero;
}

function prepareApprovedMobileLogin() {
  const page = document.querySelector(".sq-login-page");

  if (!page) {
    document.body.classList.remove("sq38-mobile-login-active");
    return false;
  }

  document.body.classList.add("sq38-mobile-login-active");
  page.classList.add("sq38-approved-mobile-login");

  // Old experimental mobile art must never reappear.
  document.getElementById("sq36-mobile-login-overlay")?.setAttribute("data-sq38-hidden", "true");

  let hero = page.querySelector(".sq37-mobile-desktop-hero");

  if (!hero) {
    hero = buildHero();
    page.insertBefore(hero, page.firstChild);
  }

  hero.classList.add("sq38-approved-hero");

  const auth = findAuthPanel(page);
  if (!auth) return true;

  auth.classList.add("sq38-approved-auth");

  const hideTargets = [
    exactText(auth, "Secure staff access"),
    exactText(auth, "Welcome back"),
    includesText(auth, "Sign in with the verified email linked to your StayQR hotel or platform account.")
  ].filter(Boolean);

  hideTargets.forEach((el) => el.classList.add("sq38-mobile-hide"));

  // Hide the duplicated StayQR brand inside the auth half on mobile.
  const brandCandidates = [...auth.querySelectorAll("div,header,section")].filter((el) => {
    const body = lower(el);
    const rect = el.getBoundingClientRect();

    return (
      body.includes("stayqr") &&
      body.includes("simplifying") &&
      rect.height > 20 &&
      rect.height < 150
    );
  });

  brandCandidates
    .sort((a, b) => {
      const ar = a.getBoundingClientRect();
      const br = b.getBoundingClientRect();
      return ar.width * ar.height - br.width * br.height;
    })
    .slice(0, 1)
    .forEach((el) => el.classList.add("sq38-mobile-hide"));

  return true;
}

function applyRev38() {
  rev38Queued = false;
  prepareApprovedMobileLogin();
}

function scheduleRev38() {
  if (rev38Queued) return;
  rev38Queued = true;
  requestAnimationFrame(applyRev38);
}

function bootRev38() {
  scheduleRev38();

  setTimeout(scheduleRev38, 100);
  setTimeout(scheduleRev38, 350);
  setTimeout(scheduleRev38, 900);
  setTimeout(scheduleRev38, 1800);

  const root = document.getElementById("root");

  if (root) {
    new MutationObserver(scheduleRev38).observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("popstate", scheduleRev38);
  window.addEventListener("hashchange", scheduleRev38);
  window.addEventListener("resize", scheduleRev38);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev38, { once: true });
} else {
  bootRev38();
}

