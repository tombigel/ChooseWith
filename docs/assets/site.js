// Copy buttons on command blocks, the docs table of contents, and the homepage demo.

const copyIcon = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><rect x="5" y="5" width="8.5" height="8.5" rx="1.8"/><path d="M10.5 5V3.8A1.8 1.8 0 0 0 8.7 2H3.8A1.8 1.8 0 0 0 2 3.8v4.9a1.8 1.8 0 0 0 1.8 1.8H5"/></svg>';
const pauseIcon = '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><rect x="4" y="3" width="3" height="10" rx="1"/><rect x="9" y="3" width="3" height="10" rx="1"/></svg>';
const playIcon = '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M5 3.2v9.6a.8.8 0 0 0 1.2.7l7.6-4.8a.8.8 0 0 0 0-1.4L6.2 2.5A.8.8 0 0 0 5 3.2z"/></svg>';
const doneIcon = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M3 8.5l3.2 3L13 4.5"/></svg>';

// Text to copy: the commands only, without prompts or "# comments".
function commandText(pre) {
  if (pre.dataset.copy) return pre.dataset.copy;
  const clone = pre.cloneNode(true);
  clone.querySelectorAll('.c, .p').forEach((n) => n.remove());
  return clone.textContent.split('\n').map((l) => l.trimEnd()).filter(Boolean).join('\n');
}

document.querySelectorAll('.cmd').forEach((block) => {
  const pre = block.querySelector('pre');
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'copy';
  btn.innerHTML = copyIcon + '<span>Copy</span>';
  btn.setAttribute('aria-label', 'Copy command');
  btn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(commandText(pre));
      btn.classList.add('done');
      btn.innerHTML = doneIcon + '<span>Copied</span>';
    } catch {
      btn.querySelector('span').textContent = 'Press ⌘C';
      const range = document.createRange();
      range.selectNodeContents(pre);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
    }
    setTimeout(() => {
      btn.classList.remove('done');
      btn.innerHTML = copyIcon + '<span>Copy</span>';
    }, 1800);
  });
  block.appendChild(btn);
});

// Docs: highlight the section being read.
const tocLinks = [...document.querySelectorAll('.toc a[href^="#"]')];
if (tocLinks.length) {
  const targets = tocLinks.map((a) => document.getElementById(a.hash.slice(1))).filter(Boolean);
  const setActive = () => {
    let current = targets[0];
    for (const t of targets) if (t.getBoundingClientRect().top < 120) current = t;
    tocLinks.forEach((a) => a.classList.toggle('active', a.hash === '#' + current.id));
  };
  addEventListener('scroll', setActive, { passive: true });
  setActive();
}

// Homepage demo: double-click a .3mf, choose a slicer from the menu.
const stage = document.querySelector('.stage');
if (stage) {
  const cursor = stage.querySelector('.cursor');
  const file = stage.querySelector('[data-file]');
  const menu = stage.querySelector('.menu');
  const items = [...menu.querySelectorAll('.it')];
  const toast = stage.querySelector('.toast');
  const toggle = document.querySelector('.demo-toggle');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let paused = reduce.matches;
  let run = 0;
  let userPaused = reduce.matches;   // paused by the button (or Reduce Motion), not by scrolling away

  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const at = (el, dx = 0.5, dy = 0.5) => {
    const s = stage.getBoundingClientRect(), r = el.getBoundingClientRect();
    return [r.left - s.left + r.width * dx, r.top - s.top + r.height * dy];
  };
  const move = (x, y) => { cursor.style.transform = `translate(${x}px, ${y}px)`; };
  const click = async () => {
    cursor.classList.remove('click');
    void cursor.offsetWidth;
    cursor.classList.add('click');
    await wait(380);
  };
  const highlight = (i) => items.forEach((it, n) => it.classList.toggle('hl', n === i));

  function reset() {
    menu.classList.remove('open');
    file.classList.remove('sel');
    toast.classList.remove('show');
    highlight(0);
    const s = stage.getBoundingClientRect();
    cursor.style.transition = 'none';
    move(s.width * 0.78, s.height * 0.82);
    void cursor.offsetWidth;
    cursor.style.transition = '';
  }

  // The finished state, for Reduce Motion and while paused.
  function still() {
    file.classList.add('sel');
    const [x, y] = at(file, 0.42, 0.6);
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';
    menu.classList.add('open');
    highlight(2);
    toast.classList.remove('show');
    const [cx, cy] = at(items[2], 0.4, 0.55);
    cursor.style.transition = 'none';
    move(cx, cy);
  }

  async function play(id) {
    const alive = () => id === run && !paused;
    while (alive()) {
      reset();
      await wait(700); if (!alive()) return;
      const [x, y] = at(file, 0.42, 0.6);
      move(x, y);
      await wait(1000); if (!alive()) return;
      file.classList.add('sel');
      await click();
      menu.style.left = x + 'px';
      menu.style.top = y + 'px';
      menu.classList.add('open');
      await wait(1300); if (!alive()) return;
      for (const i of [1, 2]) {           // look down the list of slicers
        const [ix, iy] = at(items[i], 0.4, 0.55);
        cursor.style.transitionDuration = '0.45s';
        move(ix, iy);
        await wait(500);
        highlight(i);
        await wait(650); if (!alive()) return;
      }
      cursor.style.transitionDuration = '';
      await click();
      menu.classList.remove('open');
      toast.textContent = 'Opening Coat_Hook.3mf in ' + items[2].dataset.app + '…';
      toast.classList.add('show');
      await wait(2200); if (!alive()) return;
      toast.classList.remove('show');
      await wait(600);
    }
  }

  function setPaused(p) {
    paused = p;
    run++;
    if (toggle) {
      toggle.innerHTML = (p ? playIcon : pauseIcon) + '<span>' + (p ? 'Play' : 'Pause') + '</span>';
    }
    if (p) still(); else play(run);
  }

  toggle?.addEventListener('click', () => { userPaused = !paused; setPaused(userPaused); });
  addEventListener('resize', () => { if (paused) still(); });
  // Only animate while the demo is on screen.
  new IntersectionObserver(([e]) => {
    if (userPaused) return;
    if (e.isIntersecting && paused) setPaused(false);
    else if (!e.isIntersecting && !paused) { paused = true; run++; }
  }, { threshold: 0.3 }).observe(stage);
  setPaused(paused);
}
