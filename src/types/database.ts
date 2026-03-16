// Enum types matching the SQL schema

export type ArtworkStatus =
  | 'available'
  | 'reserved'
  | 'on_loan'
  | 'in_transit'
  | 'sold'
  | 'archived';

export type TransactionType =
  | 'purchase'
  | 'sale'
  | 'consignment_in'
  | 'consignment_out'
  | 'private_sale'
  | 'auction'
  | 'return'
  | 'adjustment';

export type CurrencyCode =
  | 'USD'
  | 'EUR'
  | 'CHF'
  | 'GBP'
  | 'JPY'
  | 'HKD'
  | 'CNY'
  | 'AED'
  | 'CAD'
  | 'AUD';

export type ConditionRating =
  | 'excellent'
  | 'very_good'
  | 'good'
  | 'fair'
  | 'poor'
  | 'damaged';

export type MemberRole = 'owner' | 'admin' | 'manager' | 'viewer';

export type ContactType =
  | 'collector'
  | 'gallery'
  | 'artist'
  | 'auction_house'
  | 'institution'
  | 'advisor'
  | 'transporter'
  | 'insurer'
  | 'other';

export type DocumentType =
  | 'invoice'
  | 'certificate_of_authenticity'
  | 'condition_report'
  | 'provenance_document'
  | 'insurance_certificate'
  | 'shipping_document'
  | 'appraisal'
  | 'loan_agreement'
  | 'consignment_agreement'
  | 'purchase_agreement'
  | 'export_license'
  | 'import_license'
  | 'photo'
  | 'other';

// Table types

export interface Tenant {
  id: string;
  name: string;
  slug: string | null;
  logo_url: string | null;
  default_currency: CurrencyCode;
  default_timezone: string;
  settings: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface Profile {
  id: string;
  email: string | null;
  first_name: string | null;
  last_name: string | null;
  avatar_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface TenantMember {
  id: string;
  tenant_id: string;
  profile_id: string;
  role: MemberRole;
  invited_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface Location {
  id: string;
  tenant_id: string;
  name: string;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state_province: string | null;
  postal_code: string | null;
  country: string;
  is_default: boolean;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface Artist {
  id: string;
  tenant_id: string;
  name: string;
  birth_year: number | null;
  death_year: number | null;
  nationality: string | null;
  biography: string | null;
  website: string | null;
  created_at: string;
  updated_at: string;
}

export interface Artwork {
  id: string;
  tenant_id: string;
  inventory_number: string | null;
  title: string;
  artist_id: string | null;
  year_created: string | null;
  medium: string | null;
  dimensions: string | null;
  height_cm: number | null;
  width_cm: number | null;
  depth_cm: number | null;
  weight_kg: number | null;
  edition: string | null;
  status: ArtworkStatus;
  location_id: string | null;
  location_detail: string | null;
  purchase_price: number | null;
  purchase_currency: CurrencyCode;
  purchase_date: string | null;
  current_value: number | null;
  current_value_currency: CurrencyCode;
  insurance_value: number | null;
  insurance_currency: CurrencyCode;
  provenance: string | null;
  description: string | null;
  notes: string | null;
  condition: ConditionRating | null;
  condition_notes: string | null;
  category: string | null;
  style: string | null;
  tags: string[];
  ai_description: string | null;
  ai_tags: string[];
  is_framed: boolean;
  is_signed: boolean;
  is_authenticated: boolean;
  catalogued_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface ArtworkImage {
  id: string;
  tenant_id: string;
  artwork_id: string;
  storage_path: string;
  url: string | null;
  filename: string | null;
  mime_type: string | null;
  size_bytes: number | null;
  width_px: number | null;
  height_px: number | null;
  is_primary: boolean;
  sort_order: number;
  caption: string | null;
  created_at: string;
}

export interface Contact {
  id: string;
  tenant_id: string;
  type: ContactType;
  name: string;
  company: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  city: string | null;
  country: string | null;
  notes: string | null;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export interface Transaction {
  id: string;
  tenant_id: string;
  artwork_id: string;
  type: TransactionType;
  contact_id: string | null;
  amount: number;
  currency: CurrencyCode;
  commission_pct: number | null;
  commission_amount: number | null;
  net_amount: number | null;
  date: string;
  invoice_number: string | null;
  notes: string | null;
  consignment_start: string | null;
  consignment_end: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface Document {
  id: string;
  tenant_id: string;
  artwork_id: string | null;
  transaction_id: string | null;
  contact_id: string | null;
  type: DocumentType;
  name: string;
  storage_path: string;
  url: string | null;
  mime_type: string | null;
  size_bytes: number | null;
  notes: string | null;
  uploaded_by: string | null;
  created_at: string;
}

export interface Exhibition {
  id: string;
  tenant_id: string;
  name: string;
  venue: string | null;
  location_id: string | null;
  start_date: string | null;
  end_date: string | null;
  description: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface ExhibitionArtwork {
  id: string;
  tenant_id: string;
  exhibition_id: string;
  artwork_id: string;
  notes: string | null;
}

export interface ActivityLog {
  id: string;
  tenant_id: string;
  entity_type: string;
  entity_id: string;
  action: string;
  changes: Record<string, unknown> | null;
  performed_by: string | null;
  created_at: string;
}

export interface PdfTemplate {
  id: string;
  tenant_id: string;
  name: string;
  description: string | null;
  template_html: string;
  is_default: boolean;
  created_at: string;
  updated_at: string;
}

export interface SavedView {
  id: string;
  tenant_id: string;
  profile_id: string;
  name: string;
  entity_type: string;
  filters: Record<string, unknown>;
  sort_config: Record<string, unknown>;
  columns: unknown[];
  is_shared: boolean;
  created_at: string;
  updated_at: string;
}
