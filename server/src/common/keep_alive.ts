import type { FastifyInstance } from "fastify";

/**
 * إبقاء خدمة Render مستيقظة (Keep-alive).
 *
 * خطة Render المجانية تُنيم خدمة الويب بعد ~15 دقيقة من غياب أي طلب خارجي.
 * نرسل نبضة إلى مسار الصحة عبر العنوان العام للخدمة نفسها كل 10 دقائق،
 * فيُحتسب الطلب كزيارة خارجية وتبقى الخدمة يقظة.
 *
 * لا يعمل هذا إلا عند وجود `RENDER_EXTERNAL_URL` (يضيفه Render تلقائيًا)،
 * حتى لا نرسل طلبات لا معنى لها في التطوير المحلي.
 */
const INTERVAL_MS = 10 * 60 * 1000;
const FIRST_PING_DELAY_MS = 45 * 1000;
const REQUEST_TIMEOUT_MS = 20 * 1000;

export interface KeepAliveHandle {
  /** إيقاف النبضات (يُستدعى عند إغلاق الخادم). */
  stop: () => void;
  /** العنوان الذي تُرسل إليه النبضة، أو null عند التعطيل. */
  url: string | null;
}

export function startKeepAlive(
  app: FastifyInstance,
  externalUrl: string | undefined = process.env.RENDER_EXTERNAL_URL,
): KeepAliveHandle {
  const base = externalUrl?.trim();
  if (!base) {
    app.log.info(
      "keep-alive معطّل (RENDER_EXTERNAL_URL غير موجود) — لا حاجة للنبد في بيئة محلية.",
    );
    return { stop: () => {}, url: null };
  }

  let url: string;
  try {
    url = new URL("/api/v1/health", base).toString();
  } catch {
    app.log.warn(`keep-alive معطّل: RENDER_EXTERNAL_URL غير صالح (${base}).`);
    return { stop: () => {}, url: null };
  }

  let stopped = false;
  let lastState: "unknown" | "up" | "down" = "unknown";
  let timer: NodeJS.Timeout | null = null;
  let firstTimer: NodeJS.Timeout | null = null;

  const ping = async (): Promise<void> => {
    if (stopped) return;

    try {
      const response = await fetch(url, {
        method: "GET",
        cache: "no-store",
        headers: {
          Accept: "application/json",
          "User-Agent": "wizano-keepalive/1.0",
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      if (lastState !== "up") {
        app.log.info(`keep-alive: الخدمة تستجيب (${response.status}) — ${url}`);
      }
      lastState = "up";
    } catch (error) {
      // لا نُغرق السجل: نكتب تحذيرًا عند تغيّر الحالة فقط.
      if (lastState !== "down") {
        app.log.warn(
          { err: error instanceof Error ? error.message : String(error) },
          `keep-alive: تعذّر الوصول إلى ${url}`,
        );
      }
      lastState = "down";
    }
  };

  app.log.info(`keep-alive مفعّل: نبضة كل 10 دقائق إلى ${url}`);

  firstTimer = setTimeout(() => void ping(), FIRST_PING_DELAY_MS);
  timer = setInterval(() => void ping(), INTERVAL_MS);

  // لا نُبقي عملية Node حيّة بسبب المؤقّتات وحدها.
  firstTimer.unref();
  timer.unref();

  return {
    url,
    stop: () => {
      stopped = true;
      if (firstTimer) clearTimeout(firstTimer);
      if (timer) clearInterval(timer);
      firstTimer = null;
      timer = null;
    },
  };
}
