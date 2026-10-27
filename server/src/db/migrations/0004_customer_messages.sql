CREATE TYPE "public"."message_sender_type" AS ENUM('shop', 'customer');--> statement-breakpoint
CREATE TABLE "customer_messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"shop_id" uuid NOT NULL,
	"customer_id" uuid NOT NULL,
	"sender_user_id" uuid NOT NULL,
	"sender_type" "message_sender_type" NOT NULL,
	"body" text NOT NULL,
	"read_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "customer_messages" ADD CONSTRAINT "customer_messages_shop_id_shops_id_fk" FOREIGN KEY ("shop_id") REFERENCES "public"."shops"("id") ON DELETE restrict ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "customer_messages" ADD CONSTRAINT "customer_messages_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE restrict ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "customer_messages" ADD CONSTRAINT "customer_messages_sender_user_id_users_id_fk" FOREIGN KEY ("sender_user_id") REFERENCES "public"."users"("id") ON DELETE restrict ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "customer_messages_conversation_idx" ON "customer_messages" USING btree ("shop_id", "customer_id", "created_at");
--> statement-breakpoint
CREATE INDEX "customer_messages_unread_idx" ON "customer_messages" USING btree ("shop_id", "customer_id", "read_at");
