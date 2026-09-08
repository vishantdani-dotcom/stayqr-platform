let rev39Queued = false;

function textOf(el) {
  return String(el?.textContent || '').replace(/\s+/g, ' ').trim();
}

function lower(el) {
  return textOf(el).toLowerCase();
}

function findAuthPanel(page) {
  const candidates = [...page.querySelectorAll('section,aside,div')].filter((el) => {
    const body = lower(el);
    return body.includes('email address') && body.includes('password') && body.includes('sign in securely');
  });

  candidates.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  return candidates[0] || null;
}

function hideDuplicateBrand(auth) {
  const brandTargets = [...auth.querySelectorAll('div,header,section,a,p,span,strong,small')].filter((el) => {
    const body = lower(el);
    if (!body.includes('stayqr')) return false;
    return body.includes('simplifying');
  });

  brandTargets.sort((a, b) => {
    const ar = a.getBoundingClientRect();
    const br = b.getBoundingClientRect();
    return ar.width * ar.height - br.width * br.height;
  });

  const target = brandTargets[0];
  if (!target) return;

  let hideNode = target;
  for (let step = 0; step < 3; step += 1) {
    if (!hideNode.parentElement || hideNode.parentElement === auth) break;
    const parentText = lower(hideNode.parentElement);
    const rect = hideNode.parentElement.getBoundingClientRect();
    if (parentText.includes('stayqr') || parentText.includes('simplifying') || rect.height < 110) {
      hideNode = hideNode.parentElement;
    }
  }

  hideNode.classList.add('sq39-mobile-hide');
}

function compactLogin() {
  const page = document.querySelector('.sq-login-page');
  if (!page) {
    document.body.classList.remove('sq39-mobile-login-active');
    return false;
  }

  document.body.classList.add('sq39-mobile-login-active');
  page.classList.add('sq39-mobile-login-compact-page');

  const hero = page.querySelector('.sq37-mobile-desktop-hero, .sq38-approved-hero');
  if (hero) {
    hero.classList.add('sq39-hero-compact');
  }

  const auth = findAuthPanel(page);
  if (auth) {
    auth.classList.add('sq39-compact-auth');
    hideDuplicateBrand(auth);
  }

  return true;
}

function applyRev39() {
  rev39Queued = false;
  compactLogin();
}

function scheduleRev39() {
  if (rev39Queued) return;
  rev39Queued = true;
  requestAnimationFrame(applyRev39);
}

function bootRev39() {
  scheduleRev39();
  setTimeout(scheduleRev39, 120);
  setTimeout(scheduleRev39, 450);
  setTimeout(scheduleRev39, 1100);

  const root = document.getElementById('root');
  if (root) {
    new MutationObserver(scheduleRev39).observe(root, { childList: true, subtree: true });
  }

  window.addEventListener('resize', scheduleRev39);
  window.addEventListener('popstate', scheduleRev39);
  window.addEventListener('hashchange', scheduleRev39);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootRev39, { once: true });
} else {
  bootRev39();
}

