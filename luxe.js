// Presentation-only enhancements (scroll reveal + card tilt). No data, wallet or storage access.
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const els = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) { els.forEach((e) => e.classList.add("in")); }
  else {
    const io = new IntersectionObserver((ents) => ents.forEach((en) => { if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); } }), { rootMargin: "0px 0px -6% 0px", threshold: 0.01 });
    els.forEach((e, i) => { e.style.setProperty("--d", `${(i % 4) * 70}ms`); io.observe(e); });
  }
  if (reduce || !matchMedia("(hover: hover) and (pointer: fine)").matches) return;
  document.addEventListener("pointermove", (ev) => {
    const t = ev.target.closest && ev.target.closest(".tilt"); if (!t) return;
    const r = t.getBoundingClientRect(), x = (ev.clientX - r.left) / r.width - 0.5, y = (ev.clientY - r.top) / r.height - 0.5;
    t.style.transform = `perspective(900px) rotateY(${x * 10}deg) rotateX(${-y * 10}deg) translateY(-4px)`;
    t.style.setProperty("--mx", `${(x + 0.5) * 100}%`); t.style.setProperty("--my", `${(y + 0.5) * 100}%`);
  });
  document.addEventListener("pointerout", (ev) => { const t = ev.target.closest && ev.target.closest(".tilt"); if (t && !t.contains(ev.relatedTarget)) t.style.transform = ""; });
})();
