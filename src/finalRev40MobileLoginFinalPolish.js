let sq40Fix2Queued = false;

function sq40Fix2Text(el) {
  return String(el?.textContent || "").replace(/\s+/g, " ").trim();
}

function sq40Fix2Lower(el) {
  return sq40Fix2Text(el).toLowerCase();
}

function sq40Fix2SmallBrandBlock(leaf, page) {
  let node = leaf;
  let best = null;

  for (let depth = 0; node && node !== page && depth < 7; depth += 1) {
    const text = sq40Fix2Lower(node);
    const rect = node.getBoundingClientRect();

    if (
      text.includes("stayqr") &&
      text.includes("simplifying") &&
      rect.height > 16 &&
      rect.height < 130 &&
      rect.width > 60 &&
      rect.width < 360
    ) {
      best = node;
    }

    node = node.parentElement;
  }

  return best;
}

function sq40Fix2HideDuplicateBrands(page) {
  const leaves = [...page.querySelectorAll("*")].filter((el) => {
    if (el.children.length !== 0) return false;
    const text = sq40Fix2Lower(el);
    return text === "stayqr" || text === "simplifying checkinn";
  });

  const blocks = [];

  for (const leaf of leaves) {
    const block = sq40Fix2SmallBrandBlock(leaf, page);
    if (block && !blocks.includes(block)) blocks.push(block);
  }

  blocks.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

  blocks.slice(1).forEach((block) => {
    block.classList.add("sq40-fix2-hide-brand");
    block.style.setProperty("display", "none", "important");
    block.style.setProperty("visibility", "hidden", "important");
    block.style.setProperty("height", "0", "important");
    block.style.setProperty("min-height", "0", "important");
    block.style.setProperty("max-height", "0", "important");
    block.style.setProperty("margin", "0", "important");
    block.style.setProperty("padding", "0", "important");
    block.style.setProperty("overflow", "hidden", "important");
  });
}

function sq40Fix2FindSmallestContaining(page, phrase) {
  const needle = phrase.toLowerCase();

  const candidates = [...page.querySelectorAll("article,section,div,li")].filter((el) => {
    const text = sq40Fix2Lower(el);
    const rect = el.getBoundingClientRect();

    return (
      text.includes(needle) &&
      text.length < 320 &&
      rect.width > 55 &&
      rect.height > 24 &&
      rect.height < 220
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return (ar.width * ar.height) - (br.width * br.height);
  });

  return candidates[0] || null;
}

function sq40Fix2CompactFeatureCard(card) {
  if (!card) return;

  card.classList.add("sq40-fix2-mini-card");

  [...card.querySelectorAll("p,small,span,div")].forEach((el) => {
    const text = sq40Fix2Lower(el);

    if (
      text.includes("personalised room access") ||
      text.includes("role-aware staff") ||
      text.includes("check-in, service") ||
      text.includes("billing and room status")
    ) {
      el.classList.add("sq40-fix2-card-description");
      el.style.setProperty("display", "none", "important");
    }
  });
}

function sq40Fix2FindAuth(page) {
  const candidates = [...page.querySelectorAll("section,aside,div")].filter((el) => {
    const text = sq40Fix2Lower(el);
    const rect = el.getBoundingClientRect();

    return (
      text.includes("email address") &&
      text.includes("password") &&
      text.includes("sign in securely") &&
      text.includes("create owner account") &&
      rect.width > 180
    );
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return (ar.width * ar.height) - (br.width * br.height);
  });

  return candidates[0] || null;
}

function sq40Fix2Apply() {
  sq40Fix2Queued = false;

  const mobile = window.matchMedia("(max-width: 900px)").matches;
  const page = document.querySelector(".sq-login-page");

  if (!mobile || !page) {
    document.body.classList.remove("sq40-fix2-mobile-login-active");
    return;
  }

  document.body.classList.add("sq40-fix2-mobile-login-active");
  page.classList.add("sq40-fix2-mobile-login");

  const hero = page.querySelector(
    ".sq37-mobile-desktop-hero, .sq38-approved-hero, .sq39-hero-compact, .sq40-hero-final"
  );

  if (hero) hero.classList.add("sq40-fix2-hero");

  sq40Fix2HideDuplicateBrands(page);

  sq40Fix2CompactFeatureCard(
    sq40Fix2FindSmallestContaining(page, "qr-first guest experience")
  );
  sq40Fix2CompactFeatureCard(
    sq40Fix2FindSmallestContaining(page, "secure hotel access")
  );
  sq40Fix2CompactFeatureCard(
    sq40Fix2FindSmallestContaining(page, "operational clarity")
  );

  const auth = sq40Fix2FindAuth(page);
  if (auth) auth.classList.add("sq40-fix2-auth");
}

function sq40Fix2Schedule() {
  if (sq40Fix2Queued) return;
  sq40Fix2Queued = true;
  requestAnimationFrame(sq40Fix2Apply);
}

function sq40Fix2Boot() {
  sq40Fix2Schedule();
  setTimeout(sq40Fix2Schedule, 100);
  setTimeout(sq40Fix2Schedule, 300);
  setTimeout(sq40Fix2Schedule, 800);
  setTimeout(sq40Fix2Schedule, 1500);

  const root = document.getElementById("root");
  if (root) {
    new MutationObserver(sq40Fix2Schedule).observe(root, {
      childList: true,
      subtree: true
    });
  }

  window.addEventListener("resize", sq40Fix2Schedule);
  window.addEventListener("popstate", sq40Fix2Schedule);
  window.addEventListener("hashchange", sq40Fix2Schedule);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", sq40Fix2Boot, { once: true });
} else {
  sq40Fix2Boot();
}

