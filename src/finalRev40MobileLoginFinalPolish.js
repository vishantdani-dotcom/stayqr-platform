let sq40Queued = false;

function sq40Text(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function sq40Lower(el) {
  return sq40Text(el).toLowerCase();
}

function sq40FindAuth(page) {
  const candidates = [...page.querySelectorAll("section,aside,div")].filter((el) => {
    const t = sq40Lower(el);
    return (
      t.includes("email address") &&
      t.includes("password") &&
      t.includes("sign in securely") &&
      t.includes("create owner account")
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return (ar.width * ar.height) - (br.width * br.height);
  });

  return candidates[0] || null;
}

function sq40HideDuplicateBrand(auth) {
  if (!auth) return false;

  const candidates = [...auth.querySelectorAll("div,header,section,a,span,strong,p")].filter((el) => {
    const t = sq40Lower(el);
    const r = el.getBoundingClientRect();

    return (
      t.includes("stayqr") &&
      t.includes("simplifying") &&
      t.length < 100 &&
      r.height > 14 &&
      r.height < 120
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return (ar.width * ar.height) - (br.width * br.height);
  });

  let target = candidates[0] || null;

  if (!target) {
    const stayqrLeaves = [...auth.querySelectorAll("*")].filter((el) => {
      const t = sq40Lower(el);
      return (t === "stayqr" || t === "simplifying checkinn");
    });

    if (stayqrLeaves.length) {
      target = stayqrLeaves[0];

      for (let i = 0; i < 4 && target.parentElement && target.parentElement !== auth; i += 1) {
        const p = target.parentElement;
        const pt = sq40Lower(p);
        const pr = p.getBoundingClientRect();

        if (
          pr.height <= 120 &&
          (pt.includes("stayqr") || pt.includes("simplifying"))
        ) {
          target = p;
        } else {
          break;
        }
      }
    }
  }

  if (!target) return false;

  target.classList.add("sq40-hide-duplicate-brand");
  target.style.setProperty("display", "none", "important");
  target.style.setProperty("visibility", "hidden", "important");
  target.style.setProperty("height", "0", "important");
  target.style.setProperty("margin", "0", "important");
  target.style.setProperty("padding", "0", "important");

  return true;
}

function sq40Apply() {
  sq40Queued = false;

  const page = document.querySelector(".sq-login-page");

  if (!page) {
    document.body.classList.remove("sq40-mobile-login-active");
    return;
  }

  document.body.classList.add("sq40-mobile-login-active");
  page.classList.add("sq40-mobile-login-final");

  const hero = page.querySelector(".sq37-mobile-desktop-hero, .sq38-approved-hero, .sq39-hero-compact");
  if (hero) {
    hero.classList.add("sq40-hero-final");
  }

  const auth = sq40FindAuth(page);

  if (auth) {
    auth.classList.add("sq40-auth-final");
    sq40HideDuplicateBrand(auth);
  }
}

function sq40Schedule() {
  if (sq40Queued) return;
  sq40Queued = true;
  requestAnimationFrame(sq40Apply);
}

function sq40Boot() {
  sq40Schedule();

  setTimeout(sq40Schedule, 100);
  setTimeout(sq40Schedule, 300);
  setTimeout(sq40Schedule, 800);
  setTimeout(sq40Schedule, 1600);

  const root = document.getElementById("root");
  if (root) {
    new MutationObserver(sq40Schedule).observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("resize", sq40Schedule);
  window.addEventListener("popstate", sq40Schedule);
  window.addEventListener("hashchange", sq40Schedule);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", sq40Boot, { once: true });
} else {
  sq40Boot();
}

