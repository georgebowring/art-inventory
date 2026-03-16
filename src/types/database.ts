// Enum types matching the SQL schema

export type ArtworkStatus =
  | 'available'
  | 'reserved'
  | 'consigned'
  | 'on_loan'
  | 'in_transit'
  | 'sold'
  | 'archived'
  | 'pending_purchase'
  | 'participating'
  | 'in_wallet'
  | 'in_fabrication'
  | 'cancelled'
  | 'for_repair';

export type TransactionType =
  | 'purchase'
  | 'sale'
  | 'consignment_in'
  | 'consignment_out'
  | 'private_sale'
  | 'auction'
  | 'return'
  | 'adjustment';

export type ExpenseCategory =
  | 'shipping'
  | 'customs'
  | 'insurance'
  | 'framing'
  | 'restoration'
  | 'storage'
  | 'photography'
  | 'commission'
  | 'tax'
  | 'other';

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
  | 'factsheet'
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
  location_type: string | null;
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
  artist_ref: string | null;
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
  ownership_pct: number;
  ownership_notes: string | null;
  purchase_price: number | null;
  purchase_currency: CurrencyCode;
  purchase_date: string | null;
  acquired_from: string | null;
  current_value: number | null;
  current_value_currency: CurrencyCode;
  insurance_value: number | null;
  insurance_currency: CurrencyCode;
  consignment_price: number | null;
  consignment_currency: CurrencyCode;
  total_expenses: number;
  expenses_currency: CurrencyCode;
  cost_basis: number | null;
  cost_basis_currency: CurrencyCode;
  provenance: string | null;
  exhibition_history: string | null;
  description: string | null;
  notes: string | null;
  internal_notes: string | null;
  remarks: string | null;
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
  airtable_record_id: string | null;
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
  original_url: string | null;
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
  consignment_price: number | null;
  funds_received_date: string | null;
  profit_amount: number | null;
  profit_currency: CurrencyCode;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface Expense {
  id: string;
  tenant_id: string;
  artwork_id: string;
  category: ExpenseCategory;
  description: string | null;
  amount: number;
  currency: CurrencyCode;
  date: string;
  vendor: string | null;
  receipt_url: string | null;
  notes: string | null;
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
  original_url: string | null;
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
