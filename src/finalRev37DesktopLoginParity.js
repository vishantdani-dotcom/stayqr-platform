let rev37Queued = false;

function textOf(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function lower(el) {
  return textOf(el).toLowerCase();
}


function findNativeDesktopHero(page) {
  const candidates = [...page.querySelectorAll("section,aside,div")].filter((el) => {
    const body = lower(el);

    return (
      body.includes("one workspace") &&
      body.includes("arrival to checkout") &&
      body.includes("qr-first guest experience") &&
      body.includes("secure hotel access") &&
      body.includes("operational clarity")
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return candidates[0] || null;
}

function findAuthPanel(page) {
  const candidates = [...page.querySelectorAll("section,aside,div")].filter((el) => {
    const body = lower(el);

    return (
      body.includes("secure staff access") &&
      body.includes("email address") &&
      body.includes("password") &&
      body.includes("sign in securely")
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return candidates[0] || null;
}

function findMobileBrandInsideAuth(auth) {
  if (!auth) return null;

  const brandSignals = [...auth.querySelectorAll("div,header,section")].filter((el) => {
    const body = lower(el);
    const rect = el.getBoundingClientRect();

    return (
      body.includes("stayqr") &&
      body.includes("simplifying") &&
      !body.includes("secure staff access") &&
      rect.height > 20 &&
      rect.height < 150
    );
  });

  brandSignals.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return brandSignals[0] || null;
}

function buildFallbackHero() {
  const hero = document.createElement("section");
  hero.className = "sq37-mobile-desktop-hero sq37-generated-hero";
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

function prepareLoginParity() {
  const page = document.querySelector(".sq-login-page");

  if (!page) {
    document.body.classList.remove("sq37-login-parity-active");
    return false;
  }

  document.body.classList.add("sq37-login-parity-active");
  page.classList.add("sq37-login-parity-page");

  /*
    REV36 solved visibility but intentionally introduced a different mobile
    visual. REV37 hides those decorative overlays and reproduces the actual
    desktop composition on mobile instead.
  */
  document.getElementById("sq36-mobile-login-overlay")?.setAttribute("data-rev37-hidden", "true");

  let hero = findNativeDesktopHero(page);

  if (hero) {
    hero.classList.add("sq37-mobile-desktop-hero", "sq37-native-hero");
  } else {
    hero = page.querySelector(":scope > .sq37-generated-hero");

    if (!hero) {
      hero = buildFallbackHero();
      page.insertBefore(hero, page.firstChild);
    }
  }

  const auth = findAuthPanel(page);

  if (auth) {
    auth.classList.add("sq37-mobile-auth-panel");

    const duplicateBrand = findMobileBrandInsideAuth(auth);
    if (duplicateBrand) {
      duplicateBrand.classList.add("sq37-hide-duplicate-brand");
    }
  }

  return true;
}

function applyRev37() {
  rev37Queued = false;
  prepareLoginParity();
}

function scheduleRev37() {
  if (rev37Queued) return;
  rev37Queued = true;
  requestAnimationFrame(applyRev37);
}

function bootRev37() {
  scheduleRev37();

  setTimeout(scheduleRev37, 100);
  setTimeout(scheduleRev37, 350);
  setTimeout(scheduleRev37, 900);
  setTimeout(scheduleRev37, 1800);

  const root = document.getElementById("root");

  if (root) {
    new MutationObserver(scheduleRev37).observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("popstate", scheduleRev37);
  window.addEventListener("hashchange", scheduleRev37);
  window.addEventListener("resize", scheduleRev37);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev37, { once: true });
} else {
  bootRev37();
}


