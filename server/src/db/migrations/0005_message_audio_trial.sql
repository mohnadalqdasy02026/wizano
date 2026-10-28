ALTER TABLE "customer_messages" ALTER COLUMN "body" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "customer_messages" ADD COLUMN "audio_base64" text;--> statement-breakpoint
ALTER TABLE "customer_messages" ADD COLUMN "audio_mime_type" varchar(80);--> statement-breakpoint
ALTER TABLE "customer_messages" ADD COLUMN "audio_duration_ms" integer;
