import { z } from "zod";
export const shopIdParamSchema = z.object({ shopId: z.string().uuid() });
export const notificationIdParamSchema = z.object({ notificationId: z.string().uuid() });