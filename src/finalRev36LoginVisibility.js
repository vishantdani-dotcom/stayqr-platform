let rev36Queued = false;

function isLoginPage() {
  return !!document.querySelector(".sq-login-page");
}

function removeRev36Overlay() {
  document.getElementById("sq36-mobile-login-overlay")?.remove();
  document.body.classList.remove("sq36-login-active");
}

function ensureRev36Overlay() {
  if (!isLoginPage()) {
    removeRev36Overlay();
    return;
  }

  document.body.classList.add("sq36-login-active");

  if (document.getElementById("sq36-mobile-login-overlay")) {
    return;
  }

  const overlay = document.createElement("div");
  overlay.id = "sq36-mobile-login-overlay";
  overlay.className = "sq36-mobile-login-overlay";
  overlay.setAttribute("aria-hidden", "true");

  overlay.innerHTML = `
    <div class="sq36-ambient sq36-ambient-a"></div>
    <div class="sq36-ambient sq36-ambient-b"></div>

    <div class="sq36-grid"></div>
    <div class="sq36-scan"></div>

    <div class="sq36-visual sq36-visual-top">
      <div class="sq36-ring sq36-ring-1"></div>
      <div class="sq36-ring sq36-ring-2"></div>
      <div class="sq36-core"></div>
      <div class="sq36-qr">
        <i></i><i></i><i></i><i></i>
      </div>
      <div class="sq36-dot sq36-dot-1"></div>
      <div class="sq36-dot sq36-dot-2"></div>
    </div>

    <div class="sq36-visual sq36-visual-bottom">
      <div class="sq36-keycard">
        <div class="sq36-keycard-brand">STAYQR</div>
        <div class="sq36-keycard-room">ROOM 101</div>
        <div class="sq36-keycard-line"></div>
        <div class="sq36-keycard-copy">SECURE GUEST ACCESS</div>
      </div>
      <div class="sq36-pulse"></div>
    </div>

    <div class="sq36-particle sq36-p1"></div>
    <div class="sq36-particle sq36-p2"></div>
    <div class="sq36-particle sq36-p3"></div>
    <div class="sq36-particle sq36-p4"></div>
  `;

  /*
    Body-level placement is intentional.
    Previous attempts inserted motion inside .sq-login-page, where the
    page's own opaque layers covered it. This overlay sits outside React's
    login stacking context, so it remains visible while pointer-events:none
    guarantees it can never block sign-in controls.
  */
  document.body.appendChild(overlay);
}

function applyRev36() {
  rev36Queued = false;
  ensureRev36Overlay();
}

function scheduleRev36() {
  if (rev36Queued) return;
  rev36Queued = true;
  requestAnimationFrame(applyRev36);
}

function bootRev36() {
  scheduleRev36();

  setTimeout(scheduleRev36, 100);
  setTimeout(scheduleRev36, 350);
  setTimeout(scheduleRev36, 900);
  setTimeout(scheduleRev36, 1800);

  const root = document.getElementById("root");

  if (root) {
    new MutationObserver(scheduleRev36).observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("popstate", scheduleRev36);
  window.addEventListener("hashchange", scheduleRev36);
  window.addEventListener("resize", scheduleRev36);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRev36, { once: true });
} else {
  bootRev36();
}

