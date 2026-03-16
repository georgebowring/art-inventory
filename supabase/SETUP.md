# Art Inventory SaaS — Supabase + Clerk Setup Guide

## 1. Run the Schema SQL

1. Open your Supabase project → **SQL Editor**
2. Paste the entire contents of `schema.sql`
3. Click **Run**

> **Note on pg_vector:** The `artworks` table includes an `embedding vector(1536)` column for future AI/semantic search. If you don't have the `vector` extension enabled yet, either:
> - Enable it: Go to Database → Extensions → search "vector" → Enable
> - Or comment out the `embedding` column in the SQL and add it later

## 2. Configure Clerk JWT Template for Supabase

In your **Clerk Dashboard** → **JWT Templates** → **New Template**:

- **Name:** `supabase`
- **Signing algorithm:** HS256
- **Signing key:** Your Supabase JWT Secret (found in Supabase → Settings → API → JWT Secret)

**Claims template:**
```json
{
  "iss": "https://YOUR_CLERK_FRONTEND_API",
  "sub": "{{user.id}}",
  "org_id": "{{org.id}}",
  "org_role": "{{org_membership.role}}",
  "org_slug": "{{org.slug}}",
  "email": "{{user.primary_email_address}}",
  "first_name": "{{user.first_name}}",
  "last_name": "{{user.last_name}}",
  "aud": "authenticated",
  "exp": "{{current_timestamp_seconds + 3600}}"
}
```

> Replace `YOUR_CLERK_FRONTEND_API` with your actual Clerk Frontend API URL.

## 3. Create Supabase Storage Buckets

In **Supabase Dashboard** → **Storage**:

### Bucket: `artwork-images`
- Public: **No**
- File size limit: 20MB
- Allowed types: `image/jpeg, image/png, image/webp, image/heic`

### Bucket: `documents`
- Public: **No**
- File size limit: 50MB
- Allowed types: `application/pdf, image/jpeg, image/png`

### Storage RLS Policies
For both buckets, add these policies:

**SELECT (download):**
```sql
(storage.foldername(name))[1] = auth.clerk_org_id()
```

**INSERT (upload):**
```sql
(storage.foldername(name))[1] = auth.clerk_org_id()
```

**DELETE:**
```sql
(storage.foldername(name))[1] = auth.clerk_org_id()
```

This ensures files are organized as `{tenant_id}/...` and each tenant can only access their own files.

## 4. Set Up Clerk Webhooks

Create a Supabase Edge Function to handle Clerk webhooks for syncing users, orgs, and memberships. The schema includes helper functions:

- `sync_clerk_organization(org_id, name, slug, logo_url)`
- `sync_clerk_user(user_id, email, first_name, last_name, avatar_url)`
- `sync_clerk_membership(org_id, user_id, role)`

Subscribe to these Clerk webhook events:
- `organization.created` / `organization.updated`
- `user.created` / `user.updated`
- `organizationMembership.created` / `organizationMembership.updated`

## 5. Environment Variables Needed

```env
# Supabase
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=eyJ...

# Clerk
VITE_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
```
