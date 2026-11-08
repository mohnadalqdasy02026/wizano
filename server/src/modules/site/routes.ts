import { createReadStream, existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

/**
 * صفحة الهوية العامة (Landing page) تُخدَم من نفس خادم API.
 *
 * ملاحظة مهمة: الخادم يُجمَّع عبر tsup إلى `dist/server.js`، لذلك مسار
 * `import.meta.url` عند التشغيل لا يشبه مساره عند التطوير. نبحث عن مجلد
 * `public` في المواقع المحتملة كي يعمل الأمران: `tsx src/server.ts`
 * و`node dist/server.js` (وهو أمر Render).
 */
const moduleDir = dirname(fileURLToPath(import.meta.url));

function findPublicDir(): string {
  const candidates = [
    resolve(process.cwd(), "public"),
    resolve(moduleDir, "../public"),
    resolve(moduleDir, "../../public"),
    resolve(moduleDir, "../../../public"),
  ];

  for (const candidate of candidates) {
    if (existsSync(join(candidate, "index.html"))) return candidate;
  }

  // لا نرمي استثناءً عند الإقلاع: بقيّة مسارات API يجب أن تظل تعمل
  // حتى لو نُشر الخادم بدون مجلد public (فتُعيد الصفحة 404 JSON فقط).
  return resolve(process.cwd(), "public");
}

const PUBLIC_DIR = findPublicDir();
const ASSETS_DIR = join(PUBLIC_DIR, "assets");

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".avif": "image/avif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

/** امتدادات مسموح بها فقط — لا نخدم أي ملف آخر قد يُسقط في المجلد. */
const ALLOWED_ASSET_EXTENSIONS = new Set(Object.keys(CONTENT_TYPES));

const LONG_CACHE = "public, max-age=604800, stale-while-revalidate=86400";
const SHORT_CACHE = "public, max-age=300, must-revalidate";
const NO_CACHE = "no-cache, must-revalidate";

function isInside(parent: string, candidate: string): boolean {
  const normalizedParent = parent.endsWith(sep) ? parent : parent + sep;
  return candidate === parent || candidate.startsWith(normalizedParent);
}

function safeDecode(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

interface SendOptions {
  cacheControl: string;
  allowAnyExtension?: boolean;
}

async function sendFile(
  reply: FastifyReply,
  filePath: string,
  options: SendOptions,
): Promise<FastifyReply> {
  if (!options.allowAnyExtension) {
    const ext = extname(filePath).toLowerCase();
    if (!ALLOWED_ASSET_EXTENSIONS.has(ext)) {
      return reply.status(404).send({ error: { code: "NOT_FOUND" } });
    }
  }

  let stats;
  try {
    stats = await stat(filePath);
  } catch {
    return reply.status(404).send({ error: { code: "NOT_FOUND" } });
  }

  if (!stats.isFile()) {
    return reply.status(404).send({ error: { code: "NOT_FOUND" } });
  }

  const type =
    CONTENT_TYPES[extname(filePath).toLowerCase()] ??
    "application/octet-stream";

  return reply
    .header("Content-Type", type)
    .header("Content-Length", stats.size)
    .header("Cache-Control", options.cacheControl)
    .header("X-Content-Type-Options", "nosniff")
    .header("Last-Modified", stats.mtime.toUTCString())
    .send(createReadStream(filePath));
}

export async function registerSiteRoutes(app: FastifyInstance): Promise<void> {
  const indexFile = join(PUBLIC_DIR, "index.html");

  const sendIndex = async (
    _req: FastifyRequest,
    reply: FastifyReply,
  ): Promise<FastifyReply> =>
    sendFile(reply, indexFile, { cacheControl: NO_CACHE, allowAnyExtension: true });

  app.get("/", sendIndex);
  app.get("/index.html", sendIndex);

  app.get("/assets/*", async (request, reply) => {
    const wildcard = (request.params as { "*"?: string })["*"] ?? "";
    if (!wildcard) {
      return reply.status(404).send({ error: { code: "NOT_FOUND" } });
    }

    const decoded = safeDecode(wildcard);
    if (decoded === null || decoded.includes("\0")) {
      return reply.status(400).send({ error: { code: "BAD_REQUEST" } });
    }

    // resolve يتعامل مع `..` و`//` — ثم نتأكد أن الناتج داخل assets فقط.
    const target = resolve(ASSETS_DIR, "." + sep + decoded);
    if (!isInside(ASSETS_DIR, target)) {
      return reply.status(404).send({ error: { code: "NOT_FOUND" } });
    }

    const ext = extname(target).toLowerCase();
    const cacheControl = [".png", ".jpg", ".jpeg", ".webp", ".avif", ".svg"].includes(ext)
      ? LONG_CACHE
      : SHORT_CACHE;

    return sendFile(reply, target, { cacheControl });
  });

  app.get("/robots.txt", async (_req, reply) =>
    sendFile(reply, join(PUBLIC_DIR, "robots.txt"), {
      cacheControl: SHORT_CACHE,
      allowAnyExtension: true,
    }),
  );

  app.get("/manifest.webmanifest", async (_req, reply) =>
    sendFile(reply, join(PUBLIC_DIR, "manifest.webmanifest"), {
      cacheControl: SHORT_CACHE,
      allowAnyExtension: true,
    }),
  );

  app.get("/sitemap.xml", async (_req, reply) =>
    sendFile(reply, join(PUBLIC_DIR, "sitemap.xml"), {
      cacheControl: SHORT_CACHE,
      allowAnyExtension: true,
    }),
  );

  app.get("/favicon.ico", async (_req, reply) =>
    reply
      .header("Cache-Control", LONG_CACHE)
      .redirect("/assets/brand/logo-192.png", 302),
  );
}

export const sitePaths = {
  publicDir: PUBLIC_DIR,
} as const;
