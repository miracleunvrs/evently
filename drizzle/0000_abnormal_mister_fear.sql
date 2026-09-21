CREATE TABLE `categories` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`title` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `categories_slug_unique` ON `categories` (`slug`);--> statement-breakpoint
CREATE UNIQUE INDEX `categories_title_unique` ON `categories` (`title`);--> statement-breakpoint
CREATE TABLE `check_ins` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`ticket_id` integer NOT NULL,
	`event_id` integer NOT NULL,
	`checked_by` integer,
	`result` text DEFAULT 'ok' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE INDEX `check_ins_ticket_idx` ON `check_ins` (`ticket_id`);--> statement-breakpoint
CREATE INDEX `check_ins_event_idx` ON `check_ins` (`event_id`);--> statement-breakpoint
CREATE TABLE `event_images` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`event_id` integer NOT NULL,
	`url` text NOT NULL,
	`sort` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE INDEX `event_images_event_idx` ON `event_images` (`event_id`);--> statement-breakpoint
CREATE TABLE `events` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`organizer_id` integer NOT NULL,
	`category_id` integer,
	`title` text NOT NULL,
	`description` text DEFAULT '' NOT NULL,
	`city` text DEFAULT '' NOT NULL,
	`place` text DEFAULT '' NOT NULL,
	`starts_at` text DEFAULT '' NOT NULL,
	`capacity` integer DEFAULT 100 NOT NULL,
	`status` text DEFAULT 'published' NOT NULL,
	`cover_url` text DEFAULT '' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE INDEX `events_organizer_idx` ON `events` (`organizer_id`);--> statement-breakpoint
CREATE INDEX `events_status_idx` ON `events` (`status`);--> statement-breakpoint
CREATE INDEX `events_starts_idx` ON `events` (`starts_at`);--> statement-breakpoint
CREATE INDEX `events_category_idx` ON `events` (`category_id`);--> statement-breakpoint
CREATE TABLE `favorites` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` integer NOT NULL,
	`event_id` integer NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `favorites_user_event_unique` ON `favorites` (`user_id`,`event_id`);--> statement-breakpoint
CREATE INDEX `favorites_user_idx` ON `favorites` (`user_id`);--> statement-breakpoint
CREATE TABLE `registrations` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`event_id` integer NOT NULL,
	`user_id` integer NOT NULL,
	`status` text DEFAULT 'confirmed' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `registrations_event_user_unique` ON `registrations` (`event_id`,`user_id`);--> statement-breakpoint
CREATE INDEX `registrations_event_idx` ON `registrations` (`event_id`);--> statement-breakpoint
CREATE INDEX `registrations_user_idx` ON `registrations` (`user_id`);--> statement-breakpoint
CREATE TABLE `tickets` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`registration_id` integer NOT NULL,
	`code` text NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `tickets_registration_unique` ON `tickets` (`registration_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `tickets_code_unique` ON `tickets` (`code`);--> statement-breakpoint
CREATE INDEX `tickets_status_idx` ON `tickets` (`status`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`email` text NOT NULL,
	`name` text DEFAULT '' NOT NULL,
	`role` text DEFAULT 'visitor' NOT NULL,
	`password_hash` text DEFAULT '' NOT NULL,
	`created_at` text DEFAULT CURRENT_TIMESTAMP NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_email_unique` ON `users` (`email`);--> statement-breakpoint
CREATE INDEX `users_role_idx` ON `users` (`role`);