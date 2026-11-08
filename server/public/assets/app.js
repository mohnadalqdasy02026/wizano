/* ==========================================================================
   WIZANO | وزانو — سلوك صفحة الهوية العامة
   لا اعتماد على مكتبات خارجية، ويعمل حتى لو تعطّل JavaScript.
   ========================================================================== */

(function () {
  "use strict";

  var doc = document;

  function $(selector, scope) {
    return (scope || doc).querySelector(selector);
  }

  function $$(selector, scope) {
    return Array.prototype.slice.call((scope || doc).querySelectorAll(selector));
  }

  /* ------------------------------ شريط التنقل ----------------------------- */

  var nav = $("#nav");
  var navToggle = $("#navToggle");
  var navLinks = $("#navLinks");

  function closeMenu() {
    if (!navLinks || !navToggle) return;
    navLinks.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
    navToggle.setAttribute("aria-label", "فتح القائمة");
  }

  if (navToggle && navLinks) {
    navToggle.addEventListener("click", function () {
      var isOpen = navLinks.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
      navToggle.setAttribute("aria-label", isOpen ? "إغلاق القائمة" : "فتح القائمة");
    });

    $$("a", navLinks).forEach(function (link) {
      link.addEventListener("click", closeMenu);
    });

    doc.addEventListener("click", function (event) {
      if (!navLinks.classList.contains("is-open")) return;
      if (nav.contains(event.target)) return;
      closeMenu();
    });

    doc.addEventListener("keydown", function (event) {
      if (event.key === "Escape") closeMenu();
    });

    window.addEventListener("resize", function () {
      if (window.innerWidth > 880) closeMenu();
    });
  }

  function syncNavShadow() {
    if (!nav) return;
    nav.classList.toggle("is-scrolled", window.scrollY > 8);
  }

  syncNavShadow();
  window.addEventListener("scroll", syncNavShadow, { passive: true });

  /* -------------------------------- الحركة -------------------------------- */

  var revealItems = $$(".reveal");
  var reduceMotion =
    window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealItems.forEach(function (item) {
      item.classList.add("is-visible");
    });
  } else {
    var revealObserver = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );

    revealItems.forEach(function (item) {
      revealObserver.observe(item);
    });
  }

  /* -------------------------------- المعرض -------------------------------- */

  var tabs = $$(".tab");
  var shots = $$(".shot");
  var gallery = $("#gallery");

  function applyFilter(filter) {
    shots.forEach(function (shot) {
      var show = filter === "all" || shot.getAttribute("data-cat") === filter;
      shot.classList.toggle("is-hidden", !show);
      if (show) shot.classList.add("is-visible");
    });
  }

  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      tabs.forEach(function (other) {
        var active = other === tab;
        other.classList.toggle("is-active", active);
        other.setAttribute("aria-selected", active ? "true" : "false");
      });
      applyFilter(tab.getAttribute("data-filter") || "all");
    });

    tab.addEventListener("keydown", function (event) {
      var index = tabs.indexOf(tab);
      var next = null;

      if (event.key === "ArrowLeft") {
        next = tabs[(index + 1) % tabs.length];
      } else if (event.key === "ArrowRight") {
        next = tabs[(index - 1 + tabs.length) % tabs.length];
      } else if (event.key === "Home") {
        next = tabs[0];
      } else if (event.key === "End") {
        next = tabs[tabs.length - 1];
      }

      if (!next) return;
      event.preventDefault();
      next.focus();
      next.click();
    });
  });

  /* ------------------------------- العرض المكبّر --------------------------- */

  var lightbox = $("#lightbox");
  var lightboxImg = $("#lightboxImg");
  var lightboxCaption = $("#lightboxCaption");
  var lightboxClose = $("#lightboxClose");
  var lastFocused = null;

  function openLightbox(shot) {
    if (!lightbox || !lightboxImg || typeof lightbox.showModal !== "function") {
      return;
    }

    var img = $("img", shot);
    if (!img) return;

    var title = $("figcaption strong", shot);
    var subtitle = $("figcaption span", shot);

    lastFocused = doc.activeElement;
    lightboxImg.src = img.currentSrc || img.src;
    lightboxImg.alt = img.alt || "";
    lightboxCaption.textContent = [title ? title.textContent : "", subtitle ? subtitle.textContent : ""]
      .filter(Boolean)
      .join(" — ");

    if (!lightbox.open) lightbox.showModal();
    doc.documentElement.style.overflow = "hidden";
  }

  function closeLightbox() {
    if (!lightbox) return;
    if (typeof lightbox.close === "function" && lightbox.open) lightbox.close();
    doc.documentElement.style.overflow = "";
    lightboxImg.removeAttribute("src");
    if (lastFocused && typeof lastFocused.focus === "function") {
      lastFocused.focus();
    }
  }

  shots.forEach(function (shot) {
    shot.addEventListener("click", function () {
      openLightbox(shot);
    });

    shot.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openLightbox(shot);
      }
    });
  });

  if (lightboxClose) lightboxClose.addEventListener("click", closeLightbox);

  if (lightbox) {
    lightbox.addEventListener("click", function (event) {
      if (event.target === lightbox) closeLightbox();
    });

    lightbox.addEventListener("close", function () {
      doc.documentElement.style.overflow = "";
    });
  }

  if (gallery) {
    gallery.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && lightbox && lightbox.open) closeLightbox();
    });
  }
})();
