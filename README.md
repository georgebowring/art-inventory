# Art Inventory

Multi-tenant art inventory management SaaS built with React, Vite, and TypeScript.

## Tech Stack

- **React 19** + **Vite** + **TypeScript**
- **Tailwind CSS v4** with **shadcn/ui** (New York style)
- **Clerk** for authentication (organizations, users, roles)
- **Supabase** for database with Row Level Security
- **React Router** for navigation
- **Lucide React** for icons

## Getting Started

### 1. Install dependencies

```bash
npm install
```

### 2. Configure environment variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

You'll need:
- **Supabase** project URL and anon key
- **Clerk** publishable key

### 3. Set up Supabase and Clerk

See [`supabase/SETUP.md`](./supabase/SETUP.md) for detailed instructions on:
- Running the database schema
- Configuring the Clerk JWT template for Supabase
- Creating storage buckets
- Setting up Clerk webhooks

### 4. Run the development server

```bash
npm run dev
```

## Project Structure

```
src/
├── components/
│   ├── layout/       # AppLayout, Sidebar, Header, MobileNav
│   └── ui/           # shadcn/ui components
├── hooks/            # useSupabase hook
├── lib/              # Supabase client, utilities
├── pages/            # All route pages
└── types/            # TypeScript types matching the SQL schema
```

## Multi-Tenancy

This app uses Clerk Organizations as the tenancy model. Every data table in Supabase includes a `tenant_id` column with Row Level Security policies that restrict access to the user's active organization.

The Supabase client authenticates using Clerk JWTs via a custom JWT template that includes `org_id` and `org_role` claims.
