CREATE TABLE "customer_user_links" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"customer_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "customer_user_links" ADD CONSTRAINT "customer_user_links_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE restrict ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "customer_user_links" ADD CONSTRAINT "customer_user_links_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE UNIQUE INDEX "customer_user_links_customer_user_unique" ON "customer_user_links" USING btree ("customer_id", "user_id");
--> statement-breakpoint
CREATE INDEX "customer_user_links_user_idx" ON "customer_user_links" USING btree ("user_id");
