-- =============================================================================
-- ART INVENTORY SaaS — Complete Supabase Schema
-- Multi-tenant with Clerk authentication + Supabase RLS
-- =============================================================================
-- 
-- MULTI-TENANCY MODEL:
--   - Clerk Organizations → tenant_id (org_id from Clerk)
--   - Every data table has a tenant_id column
--   - RLS policies use a helper function that extracts the org from the JWT
--   - Users can belong to multiple orgs (galleries, collectors, etc.)
--
-- AUTH FLOW:
--   Clerk issues JWTs → Supabase verifies them via a custom JWT template
--   The JWT includes: sub (user_id), org_id, org_role, user metadata
--
-- RUN ORDER: Execute this file top-to-bottom in the Supabase SQL Editor.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";      -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "moddatetime";   -- auto-update updated_at

-- ---------------------------------------------------------------------------
-- 1. HELPER FUNCTIONS FOR RLS
-- ---------------------------------------------------------------------------

-- Extract the current user's Clerk user ID from the JWT
CREATE OR REPLACE FUNCTION auth.clerk_user_id()
RETURNS TEXT AS $$
  SELECT nullif(
    current_setting('request.jwt.claims', true)::json->>'sub',
    ''
  );
$$ LANGUAGE sql STABLE;

-- Extract the current user's active Clerk organization ID from the JWT
CREATE OR REPLACE FUNCTION auth.clerk_org_id()
RETURNS TEXT AS $$
  SELECT nullif(
    current_setting('request.jwt.claims', true)::json->>'org_id',
    ''
  );
$$ LANGUAGE sql STABLE;

-- Extract the current user's role within their active Clerk organization
CREATE OR REPLACE FUNCTION auth.clerk_org_role()
RETURNS TEXT AS $$
  SELECT nullif(
    current_setting('request.jwt.claims', true)::json->>'org_role',
    ''
  );
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------------
-- 2. ENUM TYPES
-- ---------------------------------------------------------------------------

CREATE TYPE artwork_status AS ENUM (
  'available',
  'reserved',
  'on_loan',
  'in_transit',
  'sold',
  'archived'
);

CREATE TYPE transaction_type AS ENUM (
  'purchase',
  'sale',
  'consignment_in',
  'consignment_out',
  'private_sale',
  'auction',
  'return',
  'adjustment'
);

CREATE TYPE currency_code AS ENUM (
  'USD', 'EUR', 'CHF', 'GBP', 'JPY', 'HKD', 'CNY', 'AED', 'CAD', 'AUD'
);

CREATE TYPE condition_rating AS ENUM (
  'excellent',
  'very_good',
  'good',
  'fair',
  'poor',
  'damaged'
);

CREATE TYPE member_role AS ENUM (
  'owner',
  'admin',
  'manager',
  'viewer'
);

CREATE TYPE contact_type AS ENUM (
  'collector',
  'gallery',
  'artist',
  'auction_house',
  'institution',
  'advisor',
  'transporter',
  'insurer',
  'other'
);

CREATE TYPE document_type AS ENUM (
  'invoice',
  'certificate_of_authenticity',
  'condition_report',
  'provenance_document',
  'insurance_certificate',
  'shipping_document',
  'appraisal',
  'loan_agreement',
  'consignment_agreement',
  'purchase_agreement',
  'export_license',
  'import_license',
  'photo',
  'other'
);

-- ---------------------------------------------------------------------------
-- 3. TABLES
-- ---------------------------------------------------------------------------

-- ---- 3a. TENANTS (synced from Clerk Organizations) -------------------------
CREATE TABLE tenants (
  id              TEXT PRIMARY KEY,                -- Clerk org_id
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE,
  logo_url        TEXT,
  default_currency currency_code DEFAULT 'USD',
  default_timezone TEXT DEFAULT 'America/New_York',
  settings        JSONB DEFAULT '{}'::jsonb,       -- flexible tenant config
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3b. PROFILES (synced from Clerk Users) --------------------------------
CREATE TABLE profiles (
  id              TEXT PRIMARY KEY,                -- Clerk user_id (sub)
  email           TEXT,
  first_name      TEXT,
  last_name       TEXT,
  avatar_url      TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3c. TENANT MEMBERSHIPS ------------------------------------------------
CREATE TABLE tenant_members (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  profile_id      TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role            member_role NOT NULL DEFAULT 'viewer',
  invited_by      TEXT REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (tenant_id, profile_id)
);

-- ---- 3d. LOCATIONS ---------------------------------------------------------
CREATE TABLE locations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,                   -- e.g. "Geneva Gallery", "NYC Storage"
  address_line1   TEXT,
  address_line2   TEXT,
  city            TEXT,
  state_province  TEXT,
  postal_code     TEXT,
  country         TEXT NOT NULL DEFAULT 'US',      -- ISO 3166-1 alpha-2
  is_default      BOOLEAN DEFAULT false,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3e. ARTISTS -----------------------------------------------------------
CREATE TABLE artists (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  birth_year      INT,
  death_year      INT,
  nationality     TEXT,
  biography       TEXT,
  website         TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3f. ARTWORKS (core inventory table) -----------------------------------
CREATE TABLE artworks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  
  -- Identification
  inventory_number TEXT,                           -- custom ref e.g. "FW-2024-001"
  title           TEXT NOT NULL,
  artist_id       UUID REFERENCES artists(id) ON DELETE SET NULL,
  year_created    TEXT,                            -- "2024" or "c. 1850" or "1920-1925"
  medium          TEXT,                            -- "Oil on canvas"
  dimensions      TEXT,                            -- "120 × 80 cm"
  height_cm       NUMERIC(10,2),
  width_cm        NUMERIC(10,2),
  depth_cm        NUMERIC(10,2),
  weight_kg       NUMERIC(10,2),
  edition         TEXT,                            -- "1/5 + 2 AP"
  
  -- Status & Location
  status          artwork_status DEFAULT 'available',
  location_id     UUID REFERENCES locations(id) ON DELETE SET NULL,
  location_detail TEXT,                            -- "Room 3, Wall B"
  
  -- Financials
  purchase_price  NUMERIC(14,2),
  purchase_currency currency_code DEFAULT 'USD',
  purchase_date   DATE,
  current_value   NUMERIC(14,2),                   -- latest appraisal / asking price
  current_value_currency currency_code DEFAULT 'USD',
  insurance_value NUMERIC(14,2),
  insurance_currency currency_code DEFAULT 'USD',
  
  -- Provenance & Description
  provenance      TEXT,
  description     TEXT,
  notes           TEXT,
  condition       condition_rating,
  condition_notes TEXT,
  
  -- Categorization
  category        TEXT,                            -- "Painting", "Sculpture", "Photography"
  style           TEXT,                            -- "Contemporary", "Impressionist"
  tags            TEXT[] DEFAULT '{}',
  
  -- AI & Search
  ai_description  TEXT,                            -- AI-generated description
  ai_tags         TEXT[] DEFAULT '{}',
  embedding       vector(1536),                    -- for semantic search (if pg_vector enabled)
  
  -- Metadata
  is_framed       BOOLEAN DEFAULT false,
  is_signed       BOOLEAN DEFAULT false,
  is_authenticated BOOLEAN DEFAULT false,
  catalogued_by   TEXT REFERENCES profiles(id),
  
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3g. ARTWORK IMAGES ----------------------------------------------------
CREATE TABLE artwork_images (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  artwork_id      UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
  storage_path    TEXT NOT NULL,                    -- Supabase Storage path
  url             TEXT,                             -- public/signed URL (cached)
  filename        TEXT,
  mime_type       TEXT,
  size_bytes      BIGINT,
  width_px        INT,
  height_px       INT,
  is_primary      BOOLEAN DEFAULT false,
  sort_order      INT DEFAULT 0,
  caption         TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3h. CONTACTS -----------------------------------------------------------
CREATE TABLE contacts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  type            contact_type DEFAULT 'collector',
  name            TEXT NOT NULL,
  company         TEXT,
  email           TEXT,
  phone           TEXT,
  address         TEXT,
  city            TEXT,
  country         TEXT,
  notes           TEXT,
  tags            TEXT[] DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3i. TRANSACTIONS (purchases, sales, consignments) ----------------------
CREATE TABLE transactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  artwork_id      UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
  type            transaction_type NOT NULL,
  contact_id      UUID REFERENCES contacts(id) ON DELETE SET NULL,
  
  -- Financial
  amount          NUMERIC(14,2) NOT NULL,
  currency        currency_code DEFAULT 'USD',
  commission_pct  NUMERIC(5,2),                    -- e.g. 10.00 for 10%
  commission_amount NUMERIC(14,2),
  net_amount      NUMERIC(14,2),                   -- amount after commission
  
  -- Details
  date            DATE NOT NULL DEFAULT CURRENT_DATE,
  invoice_number  TEXT,
  notes           TEXT,
  
  -- For consignments
  consignment_start DATE,
  consignment_end   DATE,
  
  created_by      TEXT REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3j. DOCUMENTS / ATTACHMENTS -------------------------------------------
CREATE TABLE documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  artwork_id      UUID REFERENCES artworks(id) ON DELETE CASCADE,
  transaction_id  UUID REFERENCES transactions(id) ON DELETE CASCADE,
  contact_id      UUID REFERENCES contacts(id) ON DELETE CASCADE,
  type            document_type DEFAULT 'other',
  name            TEXT NOT NULL,
  storage_path    TEXT NOT NULL,
  url             TEXT,
  mime_type       TEXT,
  size_bytes      BIGINT,
  notes           TEXT,
  uploaded_by     TEXT REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3k. EXHIBITIONS --------------------------------------------------------
CREATE TABLE exhibitions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  venue           TEXT,
  location_id     UUID REFERENCES locations(id) ON DELETE SET NULL,
  start_date      DATE,
  end_date        DATE,
  description     TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3l. EXHIBITION ↔ ARTWORK junction ------------------------------------
CREATE TABLE exhibition_artworks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  exhibition_id   UUID NOT NULL REFERENCES exhibitions(id) ON DELETE CASCADE,
  artwork_id      UUID NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
  notes           TEXT,
  UNIQUE (exhibition_id, artwork_id)
);

-- ---- 3m. ACTIVITY LOG (audit trail) ----------------------------------------
CREATE TABLE activity_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  entity_type     TEXT NOT NULL,                    -- 'artwork', 'transaction', etc.
  entity_id       UUID NOT NULL,
  action          TEXT NOT NULL,                    -- 'created', 'updated', 'deleted', 'status_changed'
  changes         JSONB,                            -- { field: { old: x, new: y } }
  performed_by    TEXT REFERENCES profiles(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3n. PDF TEMPLATES (for buyer presentations) ----------------------------
CREATE TABLE pdf_templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  description     TEXT,
  template_html   TEXT NOT NULL,                    -- HTML/CSS template
  is_default      BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---- 3o. SAVED VIEWS / FILTERS ---------------------------------------------
CREATE TABLE saved_views (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  profile_id      TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  entity_type     TEXT NOT NULL DEFAULT 'artwork',  -- which list this view applies to
  filters         JSONB DEFAULT '{}'::jsonb,
  sort_config     JSONB DEFAULT '{}'::jsonb,
  columns         JSONB DEFAULT '[]'::jsonb,        -- visible columns + order
  is_shared       BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4. INDEXES
-- ---------------------------------------------------------------------------

-- Tenant isolation indexes (critical for RLS performance)
CREATE INDEX idx_locations_tenant       ON locations(tenant_id);
CREATE INDEX idx_artists_tenant         ON artists(tenant_id);
CREATE INDEX idx_artworks_tenant        ON artworks(tenant_id);
CREATE INDEX idx_artwork_images_tenant  ON artwork_images(tenant_id);
CREATE INDEX idx_contacts_tenant        ON contacts(tenant_id);
CREATE INDEX idx_transactions_tenant    ON transactions(tenant_id);
CREATE INDEX idx_documents_tenant       ON documents(tenant_id);
CREATE INDEX idx_exhibitions_tenant     ON exhibitions(tenant_id);
CREATE INDEX idx_exhibition_artworks_tenant ON exhibition_artworks(tenant_id);
CREATE INDEX idx_activity_log_tenant    ON activity_log(tenant_id);
CREATE INDEX idx_pdf_templates_tenant   ON pdf_templates(tenant_id);
CREATE INDEX idx_saved_views_tenant     ON saved_views(tenant_id);
CREATE INDEX idx_tenant_members_tenant  ON tenant_members(tenant_id);
CREATE INDEX idx_tenant_members_profile ON tenant_members(profile_id);

-- Artwork search & filtering
CREATE INDEX idx_artworks_status        ON artworks(tenant_id, status);
CREATE INDEX idx_artworks_artist        ON artworks(tenant_id, artist_id);
CREATE INDEX idx_artworks_location      ON artworks(tenant_id, location_id);
CREATE INDEX idx_artworks_category      ON artworks(tenant_id, category);
CREATE INDEX idx_artworks_inventory_num ON artworks(tenant_id, inventory_number);
CREATE INDEX idx_artworks_tags          ON artworks USING gin(tags);
CREATE INDEX idx_artworks_title_search  ON artworks USING gin(to_tsvector('english', coalesce(title, '')));

-- Transaction lookups
CREATE INDEX idx_transactions_artwork   ON transactions(tenant_id, artwork_id);
CREATE INDEX idx_transactions_contact   ON transactions(tenant_id, contact_id);
CREATE INDEX idx_transactions_date      ON transactions(tenant_id, date);
CREATE INDEX idx_transactions_type      ON transactions(tenant_id, type);

-- Image lookups
CREATE INDEX idx_artwork_images_artwork ON artwork_images(artwork_id);

-- Document lookups
CREATE INDEX idx_documents_artwork      ON documents(artwork_id);
CREATE INDEX idx_documents_transaction  ON documents(transaction_id);

-- Activity log
CREATE INDEX idx_activity_log_entity    ON activity_log(tenant_id, entity_type, entity_id);
CREATE INDEX idx_activity_log_date      ON activity_log(tenant_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 5. AUTO-UPDATE updated_at TRIGGERS
-- ---------------------------------------------------------------------------

CREATE TRIGGER set_updated_at_tenants
  BEFORE UPDATE ON tenants
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_tenant_members
  BEFORE UPDATE ON tenant_members
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_locations
  BEFORE UPDATE ON locations
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_artists
  BEFORE UPDATE ON artists
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_artworks
  BEFORE UPDATE ON artworks
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_contacts
  BEFORE UPDATE ON contacts
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_transactions
  BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_exhibitions
  BEFORE UPDATE ON exhibitions
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_pdf_templates
  BEFORE UPDATE ON pdf_templates
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TRIGGER set_updated_at_saved_views
  BEFORE UPDATE ON saved_views
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ---------------------------------------------------------------------------

-- Enable RLS on all tenant-scoped tables
ALTER TABLE tenants             ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members      ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations           ENABLE ROW LEVEL SECURITY;
ALTER TABLE artists             ENABLE ROW LEVEL SECURITY;
ALTER TABLE artworks            ENABLE ROW LEVEL SECURITY;
ALTER TABLE artwork_images      ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents           ENABLE ROW LEVEL SECURITY;
ALTER TABLE exhibitions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE exhibition_artworks ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdf_templates       ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_views         ENABLE ROW LEVEL SECURITY;

-- ---- TENANTS ---------------------------------------------------------------
-- Users can see tenants they belong to
CREATE POLICY "tenants_select" ON tenants FOR SELECT USING (
  id = auth.clerk_org_id()
);
-- Only org admins/owners can update tenant settings
CREATE POLICY "tenants_update" ON tenants FOR UPDATE USING (
  id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- ---- PROFILES --------------------------------------------------------------
-- Users can see their own profile
CREATE POLICY "profiles_select_own" ON profiles FOR SELECT USING (
  id = auth.clerk_user_id()
);
-- Users can see profiles of members in their org
CREATE POLICY "profiles_select_org" ON profiles FOR SELECT USING (
  id IN (
    SELECT profile_id FROM tenant_members WHERE tenant_id = auth.clerk_org_id()
  )
);
-- Users can update their own profile
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE USING (
  id = auth.clerk_user_id()
);
-- Allow insert for new user sync (from webhooks / service role)
CREATE POLICY "profiles_insert" ON profiles FOR INSERT WITH CHECK (
  id = auth.clerk_user_id()
);

-- ---- TENANT MEMBERS --------------------------------------------------------
CREATE POLICY "tenant_members_select" ON tenant_members FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "tenant_members_insert" ON tenant_members FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);
CREATE POLICY "tenant_members_update" ON tenant_members FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);
CREATE POLICY "tenant_members_delete" ON tenant_members FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- ---- STANDARD TENANT-SCOPED POLICY TEMPLATE --------------------------------
-- The following macro-like pattern applies to all data tables:
--   SELECT: tenant_id must match the JWT org_id
--   INSERT: tenant_id must match the JWT org_id
--   UPDATE: tenant_id must match the JWT org_id AND user is not a viewer
--   DELETE: tenant_id must match the JWT org_id AND user is admin/owner

-- LOCATIONS
CREATE POLICY "locations_select" ON locations FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "locations_insert" ON locations FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "locations_update" ON locations FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "locations_delete" ON locations FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- ARTISTS
CREATE POLICY "artists_select" ON artists FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artists_insert" ON artists FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artists_update" ON artists FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "artists_delete" ON artists FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- ARTWORKS
CREATE POLICY "artworks_select" ON artworks FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artworks_insert" ON artworks FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artworks_update" ON artworks FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "artworks_delete" ON artworks FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- ARTWORK IMAGES
CREATE POLICY "artwork_images_select" ON artwork_images FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artwork_images_insert" ON artwork_images FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artwork_images_update" ON artwork_images FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "artwork_images_delete" ON artwork_images FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);

-- CONTACTS
CREATE POLICY "contacts_select" ON contacts FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "contacts_insert" ON contacts FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "contacts_update" ON contacts FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "contacts_delete" ON contacts FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- TRANSACTIONS
CREATE POLICY "transactions_select" ON transactions FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "transactions_insert" ON transactions FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "transactions_update" ON transactions FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);
CREATE POLICY "transactions_delete" ON transactions FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- DOCUMENTS
CREATE POLICY "documents_select" ON documents FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "documents_insert" ON documents FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "documents_update" ON documents FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "documents_delete" ON documents FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- EXHIBITIONS
CREATE POLICY "exhibitions_select" ON exhibitions FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "exhibitions_insert" ON exhibitions FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "exhibitions_update" ON exhibitions FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);
CREATE POLICY "exhibitions_delete" ON exhibitions FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- EXHIBITION_ARTWORKS
CREATE POLICY "exhibition_artworks_select" ON exhibition_artworks FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "exhibition_artworks_insert" ON exhibition_artworks FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "exhibition_artworks_update" ON exhibition_artworks FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "exhibition_artworks_delete" ON exhibition_artworks FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() NOT IN ('org:member')
);

-- ACTIVITY LOG (append-only for most users)
CREATE POLICY "activity_log_select" ON activity_log FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "activity_log_insert" ON activity_log FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
);
-- No update/delete policies — activity log is immutable

-- PDF TEMPLATES
CREATE POLICY "pdf_templates_select" ON pdf_templates FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
);
CREATE POLICY "pdf_templates_insert" ON pdf_templates FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);
CREATE POLICY "pdf_templates_update" ON pdf_templates FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);
CREATE POLICY "pdf_templates_delete" ON pdf_templates FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND auth.clerk_org_role() IN ('org:admin', 'admin', 'owner')
);

-- SAVED VIEWS
CREATE POLICY "saved_views_select" ON saved_views FOR SELECT USING (
  tenant_id = auth.clerk_org_id()
  AND (
    profile_id = auth.clerk_user_id()  -- own views
    OR is_shared = true                 -- shared views in same org
  )
);
CREATE POLICY "saved_views_insert" ON saved_views FOR INSERT WITH CHECK (
  tenant_id = auth.clerk_org_id()
  AND profile_id = auth.clerk_user_id()
);
CREATE POLICY "saved_views_update" ON saved_views FOR UPDATE USING (
  tenant_id = auth.clerk_org_id()
  AND profile_id = auth.clerk_user_id()
);
CREATE POLICY "saved_views_delete" ON saved_views FOR DELETE USING (
  tenant_id = auth.clerk_org_id()
  AND profile_id = auth.clerk_user_id()
);

-- ---------------------------------------------------------------------------
-- 7. SUPABASE STORAGE BUCKETS (run via Dashboard or Storage API)
-- ---------------------------------------------------------------------------
-- These need to be created via the Supabase Dashboard > Storage section:
--
-- Bucket: artwork-images
--   - Public: false (use signed URLs)
--   - File size limit: 20MB
--   - Allowed MIME types: image/jpeg, image/png, image/webp, image/heic
--
-- Bucket: documents
--   - Public: false
--   - File size limit: 50MB
--   - Allowed MIME types: application/pdf, image/jpeg, image/png, 
--     application/msword, application/vnd.openxmlformats-officedocument.*
--
-- Storage RLS policies (apply in Dashboard > Storage > Policies):
--
-- artwork-images bucket:
--   SELECT: (storage.foldername(name))[1] = auth.clerk_org_id()
--   INSERT: (storage.foldername(name))[1] = auth.clerk_org_id()
--   DELETE: (storage.foldername(name))[1] = auth.clerk_org_id()
--
-- Upload path convention: {tenant_id}/{artwork_id}/{filename}
-- Document path convention: {tenant_id}/docs/{document_id}/{filename}

-- ---------------------------------------------------------------------------
-- 8. UTILITY FUNCTIONS
-- ---------------------------------------------------------------------------

-- Calculate P&L for an artwork (purchase vs. sale)
CREATE OR REPLACE FUNCTION get_artwork_pnl(p_artwork_id UUID)
RETURNS TABLE (
  purchase_total NUMERIC,
  purchase_currency currency_code,
  sale_total NUMERIC,
  sale_currency currency_code,
  profit_loss NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH purchases AS (
    SELECT COALESCE(SUM(amount), 0) as total, 
           COALESCE(MIN(currency), 'USD') as curr
    FROM transactions 
    WHERE artwork_id = p_artwork_id 
    AND type IN ('purchase', 'consignment_in')
  ),
  sales AS (
    SELECT COALESCE(SUM(net_amount), COALESCE(SUM(amount), 0)) as total,
           COALESCE(MIN(currency), 'USD') as curr
    FROM transactions 
    WHERE artwork_id = p_artwork_id 
    AND type IN ('sale', 'private_sale', 'auction')
  )
  SELECT 
    p.total as purchase_total,
    p.curr as purchase_currency,
    s.total as sale_total,
    s.curr as sale_currency,
    (s.total - p.total) as profit_loss
  FROM purchases p, sales s;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Auto-generate inventory number
CREATE OR REPLACE FUNCTION generate_inventory_number()
RETURNS TRIGGER AS $$
DECLARE
  prefix TEXT;
  next_num INT;
BEGIN
  IF NEW.inventory_number IS NULL OR NEW.inventory_number = '' THEN
    -- Get tenant slug or first 2 chars of name as prefix
    SELECT COALESCE(slug, UPPER(LEFT(name, 2))) INTO prefix FROM tenants WHERE id = NEW.tenant_id;
    prefix := UPPER(COALESCE(prefix, 'XX'));
    
    -- Get next number for this tenant
    SELECT COALESCE(MAX(
      CASE 
        WHEN inventory_number ~ ('^' || prefix || '-\d{4}-\d+$')
        THEN CAST(SPLIT_PART(inventory_number, '-', 3) AS INT)
        ELSE 0
      END
    ), 0) + 1
    INTO next_num
    FROM artworks
    WHERE tenant_id = NEW.tenant_id;
    
    NEW.inventory_number := prefix || '-' || EXTRACT(YEAR FROM now()) || '-' || LPAD(next_num::TEXT, 4, '0');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_inventory_number
  BEFORE INSERT ON artworks
  FOR EACH ROW EXECUTE FUNCTION generate_inventory_number();

-- Auto-update artwork status when a sale transaction is recorded
CREATE OR REPLACE FUNCTION update_artwork_status_on_transaction()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type IN ('sale', 'private_sale', 'auction') THEN
    UPDATE artworks SET status = 'sold' WHERE id = NEW.artwork_id;
  ELSIF NEW.type = 'consignment_out' THEN
    UPDATE artworks SET status = 'on_loan' WHERE id = NEW.artwork_id;
  ELSIF NEW.type = 'return' THEN
    UPDATE artworks SET status = 'available' WHERE id = NEW.artwork_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER artwork_status_on_transaction
  AFTER INSERT ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_artwork_status_on_transaction();

-- Log activity automatically
CREATE OR REPLACE FUNCTION log_activity()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO activity_log (tenant_id, entity_type, entity_id, action, performed_by)
    VALUES (NEW.tenant_id, TG_TABLE_NAME, NEW.id, 'created', auth.clerk_user_id());
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO activity_log (tenant_id, entity_type, entity_id, action, changes, performed_by)
    VALUES (
      NEW.tenant_id, 
      TG_TABLE_NAME, 
      NEW.id, 
      'updated',
      jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW)),
      auth.clerk_user_id()
    );
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO activity_log (tenant_id, entity_type, entity_id, action, changes, performed_by)
    VALUES (OLD.tenant_id, TG_TABLE_NAME, OLD.id, 'deleted', to_jsonb(OLD), auth.clerk_user_id());
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Apply activity logging to key tables
CREATE TRIGGER log_artworks_activity
  AFTER INSERT OR UPDATE OR DELETE ON artworks
  FOR EACH ROW EXECUTE FUNCTION log_activity();

CREATE TRIGGER log_transactions_activity
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION log_activity();

CREATE TRIGGER log_contacts_activity
  AFTER INSERT OR UPDATE OR DELETE ON contacts
  FOR EACH ROW EXECUTE FUNCTION log_activity();

-- ---------------------------------------------------------------------------
-- 9. CLERK WEBHOOK SYNC FUNCTIONS
-- ---------------------------------------------------------------------------
-- These are called by your Edge Functions when Clerk fires webhooks.
-- They keep tenants, profiles, and memberships in sync.

-- Upsert a tenant from Clerk org data
CREATE OR REPLACE FUNCTION sync_clerk_organization(
  p_org_id TEXT,
  p_name TEXT,
  p_slug TEXT DEFAULT NULL,
  p_logo_url TEXT DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO tenants (id, name, slug, logo_url)
  VALUES (p_org_id, p_name, p_slug, p_logo_url)
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    slug = COALESCE(EXCLUDED.slug, tenants.slug),
    logo_url = COALESCE(EXCLUDED.logo_url, tenants.logo_url),
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Upsert a profile from Clerk user data
CREATE OR REPLACE FUNCTION sync_clerk_user(
  p_user_id TEXT,
  p_email TEXT DEFAULT NULL,
  p_first_name TEXT DEFAULT NULL,
  p_last_name TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO profiles (id, email, first_name, last_name, avatar_url)
  VALUES (p_user_id, p_email, p_first_name, p_last_name, p_avatar_url)
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, profiles.email),
    first_name = COALESCE(EXCLUDED.first_name, profiles.first_name),
    last_name = COALESCE(EXCLUDED.last_name, profiles.last_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, profiles.avatar_url),
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Upsert a tenant membership from Clerk org membership data
CREATE OR REPLACE FUNCTION sync_clerk_membership(
  p_org_id TEXT,
  p_user_id TEXT,
  p_role TEXT DEFAULT 'viewer'
)
RETURNS void AS $$
DECLARE
  v_role member_role;
BEGIN
  -- Map Clerk roles to our enum
  v_role := CASE p_role
    WHEN 'org:admin' THEN 'admin'::member_role
    WHEN 'org:member' THEN 'viewer'::member_role
    WHEN 'admin' THEN 'admin'::member_role
    WHEN 'owner' THEN 'owner'::member_role
    ELSE 'viewer'::member_role
  END;
  
  INSERT INTO tenant_members (tenant_id, profile_id, role)
  VALUES (p_org_id, p_user_id, v_role)
  ON CONFLICT (tenant_id, profile_id) DO UPDATE SET
    role = EXCLUDED.role,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- 10. DASHBOARD VIEWS (for common queries)
-- ---------------------------------------------------------------------------

-- Inventory summary by status
CREATE OR REPLACE VIEW inventory_summary AS
SELECT 
  tenant_id,
  status,
  COUNT(*) as count,
  SUM(current_value) as total_value,
  current_value_currency
FROM artworks
GROUP BY tenant_id, status, current_value_currency;

-- Recent activity feed
CREATE OR REPLACE VIEW recent_activity AS
SELECT 
  al.id,
  al.tenant_id,
  al.entity_type,
  al.entity_id,
  al.action,
  al.changes,
  al.created_at,
  p.first_name || ' ' || p.last_name as performed_by_name,
  p.avatar_url as performed_by_avatar
FROM activity_log al
LEFT JOIN profiles p ON p.id = al.performed_by
ORDER BY al.created_at DESC;

-- Artwork detail view (with artist and location)
CREATE OR REPLACE VIEW artwork_details AS
SELECT 
  a.*,
  ar.name as artist_name,
  ar.nationality as artist_nationality,
  l.name as location_name,
  l.city as location_city,
  l.country as location_country,
  (SELECT url FROM artwork_images WHERE artwork_id = a.id AND is_primary = true LIMIT 1) as primary_image_url,
  (SELECT COUNT(*) FROM artwork_images WHERE artwork_id = a.id) as image_count
FROM artworks a
LEFT JOIN artists ar ON ar.id = a.artist_id
LEFT JOIN locations l ON l.id = a.location_id;

-- =========================================================================
-- DONE! Next steps:
-- 1. Run this SQL in your Supabase SQL Editor
-- 2. Create storage buckets via Dashboard (see Section 7)
-- 3. Set up Clerk JWT template to include org_id and org_role
-- 4. Deploy Clerk webhook Edge Functions for user/org sync
-- =========================================================================
