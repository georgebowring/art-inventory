#!/usr/bin/env python3
"""
Airtable → Supabase Migration Script
=====================================
Reads raw Airtable JSON exports and generates:
  1. A complete SQL file with all INSERT statements
  2. A CSV summary of all migrated records for verification
  3. A data quality report of skipped/problematic records

Usage:
  python migrate.py --tenant-id YOUR_CLERK_ORG_ID

The generated SQL file can be run directly in the Supabase SQL Editor.
"""

import json
import re
import sys
import csv
import argparse
from pathlib import Path
from datetime import datetime
from collections import defaultdict
import uuid

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MIGRATION_DIR = Path("/home/user/workspace/migration")
STOCK_FILE = MIGRATION_DIR / "airtable_stock_raw.json"
VENDU_FILE = MIGRATION_DIR / "airtable_vendu_raw.json"
OUTPUT_SQL = MIGRATION_DIR / "migration_data.sql"
OUTPUT_CSV = MIGRATION_DIR / "migration_summary.csv"
OUTPUT_REPORT = MIGRATION_DIR / "migration_report.md"

# ---------------------------------------------------------------------------
# Status Mapping
# ---------------------------------------------------------------------------
STATUS_MAP = {
    "In Stock": "available",
    "In Stock ": "available",      # trailing space variant
    "Consigned": "consigned",
    "Sold": "sold",
    "Sold Particip": "sold",
    "En cours d'achat": "pending_purchase",
    "Particip.": "participating",
    "In Wallet": "in_wallet",
    "In Transit": "in_transit",
    "Prêté": "on_loan",
    "Sans suite": "cancelled",
    "En Fabrication": "in_fabrication",
    "For repair": "for_repair",
    "Cancelled": "cancelled",
}

# ---------------------------------------------------------------------------
# Currency validation
# ---------------------------------------------------------------------------
VALID_CURRENCIES = {"USD", "EUR", "CHF", "GBP", "HKD", "JPY", "CNY", "AED", "CAD", "AUD"}

def clean_currency(val):
    """Extract valid currency code from messy select field."""
    if not val:
        return "USD"
    val = val.strip()
    if val in VALID_CURRENCIES:
        return val
    # Some entries have leading/trailing spaces or mixed content
    for c in VALID_CURRENCIES:
        if c in val.upper():
            return c
    return "USD"  # default

# ---------------------------------------------------------------------------
# Ownership parsing
# ---------------------------------------------------------------------------
def parse_ownership(val):
    """Parse ownership string into percentage and notes."""
    if not val:
        return 100.0, None
    
    val = val.strip()
    
    # Direct percentage
    if val.endswith("%"):
        try:
            num = val.replace("%", "").replace(",", ".").strip()
            return float(num), val
        except ValueError:
            pass
    
    # "Propriété" = 100%
    if val.lower() in ("propriété", "propriete"):
        return 100.0, "Propriété"
    
    # Fractions: "1/3", "2/3", "1/2", etc.
    frac_match = re.match(r"^(\d+)\s*/\s*(\d+)$", val)
    if frac_match:
        num, den = int(frac_match.group(1)), int(frac_match.group(2))
        if den > 0:
            return round((num / den) * 100, 4), val
    
    # "100.00%" or "100,00%"
    pct_match = re.match(r"^([\d,.]+)\s*%?$", val)
    if pct_match:
        try:
            num = pct_match.group(1).replace(",", ".")
            return float(num), val
        except ValueError:
            pass
    
    # Edition notation: "Ed. 4 of 5 + 2AP" — treat as 100% ownership of that edition
    if val.lower().startswith("ed.") or "unique" in val.lower():
        return 100.0, val
    
    return 100.0, val

# ---------------------------------------------------------------------------
# Location cleaning
# ---------------------------------------------------------------------------
# Locations that are actually statuses or junk, not real locations
JUNK_LOCATIONS = {
    "sold", "sans suite", "offert", "returned", "cancelled",
    "en cours livraison", "en fabrication", "in transit",
}

def clean_location_name(val):
    """Clean location name, return None if it's junk."""
    if not val:
        return None
    val = val.strip()
    # Skip entries that start with $ (dollar amounts that leaked in)
    if val.startswith("$"):
        return None
    # Skip known junk
    if val.lower().strip().rstrip("!").strip() in JUNK_LOCATIONS:
        return None
    # Skip delivery instructions that aren't actual locations
    if val.lower().startswith("livrer"):
        # "Livrer Harsch" → "Harsch" (pending delivery)
        parts = val.split(" ", 1)
        if len(parts) > 1:
            return parts[1].strip()
        return None
    # Clean "Sold          !!!!! c/o Harsch" → "Harsch"
    if "c/o" in val.lower():
        parts = val.lower().split("c/o")
        if len(parts) > 1:
            return parts[1].strip().title()
    # Clean trailing whitespace and normalize
    val = val.strip()
    # Normalize "14 T" and "14T" → "14T"
    if val in ("14 T", "14 T "):
        return "14T"
    if val in ("Harsch ", "Harch"):
        return "Harsch"
    if val.startswith("UOVO"):
        return val  # keep UOVO variants as-is
    if val.startswith("Wallet Stagadon"):
        return "Wallet Stagadon"
    return val

# ---------------------------------------------------------------------------
# Contact type guessing
# ---------------------------------------------------------------------------
AUCTION_HOUSES = {"sotheby's", "christie's", "phillips", "bonhams", "piasa", "wright", 
                  "giquello", "roseberys", "swann", "fair warning"}
GALLERIES_KEYWORDS = {"gallery", "galerie", "projects", "contemporary", "fine art"}

def guess_contact_type(name):
    """Guess contact type from name."""
    name_lower = name.lower()
    for ah in AUCTION_HOUSES:
        if ah in name_lower:
            return "auction_house"
    for gk in GALLERIES_KEYWORDS:
        if gk in name_lower:
            return "gallery"
    return "gallery"  # default for art world

# ---------------------------------------------------------------------------
# SQL helpers
# ---------------------------------------------------------------------------
def sql_str(val):
    """Escape a value for SQL string literal."""
    if val is None:
        return "NULL"
    val = str(val).replace("'", "''")
    return f"'{val}'"

def sql_num(val):
    """Format a number for SQL."""
    if val is None:
        return "NULL"
    try:
        return str(float(val))
    except (ValueError, TypeError):
        return "NULL"

def sql_date(val):
    """Format a date for SQL."""
    if not val:
        return "NULL"
    # Airtable dates are ISO format: 2024-01-15
    return f"'{val}'"

def sql_bool(val):
    """Format a boolean for SQL."""
    if val is None:
        return "false"
    return "true" if val else "false"

# ---------------------------------------------------------------------------
# Main migration logic
# ---------------------------------------------------------------------------
def load_records(filepath):
    """Load Airtable records from JSON file."""
    with open(filepath) as f:
        data = json.load(f)
    # Handle both direct array and {result: [...]} wrapper
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        if "result" in data:
            return data["result"]
        # Connector output format
        for key in data:
            if isinstance(data[key], list):
                return data[key]
    return []

def migrate(tenant_id):
    """Run the full migration."""
    
    print(f"Loading Airtable data...")
    stock_records = load_records(STOCK_FILE)
    vendu_records = load_records(VENDU_FILE)
    print(f"  Stock: {len(stock_records)} records")
    print(f"  Vendu: {len(vendu_records)} records")
    
    # Collect unique entities
    artists = {}       # name → uuid
    locations = {}     # cleaned_name → uuid
    contacts = {}      # name → uuid
    artworks = []      # list of artwork dicts
    transactions = []  # list of transaction dicts
    expenses_list = [] # list of expense dicts
    images = []        # list of image dicts
    documents = []     # list of document dicts
    
    issues = []        # data quality issues
    csv_rows = []      # for summary CSV
    
    # Track Airtable record IDs to avoid duplicates between Stock and Vendu
    seen_airtable_ids = set()
    
    def process_record(rec, source_table):
        """Process a single Airtable record."""
        fields = rec.get("fields", {})
        airtable_id = rec.get("id", "")
        
        # Skip if we've already seen this record
        if airtable_id in seen_airtable_ids:
            issues.append(f"Duplicate record {airtable_id} in {source_table}, skipped")
            return
        seen_airtable_ids.add(airtable_id)
        
        # ---- Extract fields based on source table ----
        if source_table == "Stock":
            artist_name = fields.get("Artist", "").strip() or None
            title = fields.get("Title", "").strip() or None
            ref_stag = fields.get("Ref Stag", "")
            ref_artist = fields.get("Ref Artist", "")
            year = fields.get("Date")  # number field
            medium = fields.get("Medium", "")
            dimensions = fields.get("Dimensions", "")
            status_raw = fields.get("Status", "")
            provenance = fields.get("Provenance", "")
            exhibition_history = fields.get("Exhibition History", "")
            acquired_from_raw = fields.get("Acquired from", "")
            ownership_raw = fields.get("Ownership", "")
            currency_raw = fields.get("Currency", "")
            buy_price = fields.get("Buy price")
            expense_currency_raw = fields.get("Currency Expenses", "")
            expense_amount = fields.get("Expenses")
            storage_location_raw = fields.get("Storage Location", "")
            comments = fields.get("Comments", "")
            loic_instructions = fields.get("Loic instructions", "")
            est_value = fields.get("Est. Value USD")
            consignment_price = fields.get("Prix Consigné")
            sale_currency_raw = fields.get("Currency Sold", "")
            sale_price = fields.get("Sale Price")
            sale_date = fields.get("Date de vente")
            sold_to_raw = fields.get("Sold to:", "")
            profit_usd = fields.get("Profit USD")
            funds_received = fields.get("Date Funds Received")
            remarks = fields.get("Remarks", "")
            stock_value = fields.get("Stock Value USD")
            date_bought = fields.get("Date bought")
            pictures = fields.get("Picture", [])
            pdfs = fields.get("Pdf", [])
        else:
            # Vendu table has different field names
            artist_name = fields.get("Artiste", "").strip() or None
            title_raw = fields.get("Titre, date", "")
            # Vendu title field may have combined title + date
            title = title_raw.strip() if title_raw else None
            ref_stag = str(fields.get("Ref Stag", "")) if fields.get("Ref Stag") else ""
            ref_artist = fields.get("Réf              Artiste", "")
            year = None  # Vendu doesn't have a separate year field
            medium = fields.get("Technique", "")
            dimensions = fields.get("Dimensions", "")
            status_raw = fields.get("Status", "Sold")  # Vendu = sold
            provenance = ""
            exhibition_history = ""
            acquired_from_raw = fields.get("Achat à", "")
            ownership_raw = fields.get("Propriété", "")
            currency_raw = fields.get("Monnaie Achat", "")
            buy_price = fields.get("Prix d'achat")
            expense_currency_raw = fields.get("Frais Monnaie", "")
            expense_amount = fields.get("Frais")
            storage_location_raw = fields.get("Lieu Depot", "")
            comments = fields.get("Remarques", "")
            loic_instructions = ""
            est_value = None
            consignment_price = None
            sale_currency_raw = fields.get("Monnaie Vente", "")
            sale_price = fields.get("Prix de Vente")
            sale_date = fields.get("Date vente")
            sold_to_raw = fields.get("Vendu à", "")
            profit_usd = fields.get("Profit")
            funds_received = fields.get("Funds Reçu", fields.get("Date Funds Received"))
            remarks = ""
            stock_value = None
            date_bought = fields.get("Date d'achat copy")
            pictures = fields.get("Photo", [])
            pdfs = []
        
        # ---- Skip records with no title ----
        if not title:
            issues.append(f"Record {airtable_id} ({source_table}): No title, skipped. Fields present: {list(fields.keys())}")
            return
        
        # ---- Process Artist ----
        artist_uuid = None
        if artist_name and artist_name.strip():
            artist_name = artist_name.strip()
            # Normalize known variants
            if artist_name == "Xiniy Cheng":
                artist_name = "Xinyi Cheng"
            if artist_name == "Cyperien Galliard":
                artist_name = "Cyprien Gaillard"
            if artist_name == "René Margritte":
                artist_name = "René Magritte"
            if artist_name == "Dsvid Kordansky":
                artist_name = "David Kordansky Gallery"
                
            if artist_name not in artists:
                artists[artist_name] = str(uuid.uuid4())
            artist_uuid = artists[artist_name]
        
        # ---- Process Location ----
        location_uuid = None
        loc_name = clean_location_name(storage_location_raw)
        if loc_name:
            if loc_name not in locations:
                locations[loc_name] = str(uuid.uuid4())
            location_uuid = locations[loc_name]
        
        # ---- Process "Acquired From" as Contact ----
        acquired_contact_uuid = None
        acquired_from = acquired_from_raw.strip() if acquired_from_raw else ""
        # Filter out junk values (percentages, amounts, dimensions)
        if acquired_from and not acquired_from.startswith("$") and not re.match(r"^[\d,./%]+$", acquired_from) and not re.match(r"^\d+\s*x\s*\d+", acquired_from, re.I):
            if acquired_from not in contacts:
                contacts[acquired_from] = str(uuid.uuid4())
            acquired_contact_uuid = contacts[acquired_from]
        
        # ---- Process "Sold To" as Contact ----
        sold_contact_uuid = None
        sold_to = sold_to_raw.strip() if sold_to_raw else ""
        # Filter junk (dates and amounts that leaked into this field)
        if sold_to and not re.match(r"^\d+/\d+/\d+$", sold_to) and not sold_to.startswith("$") and not sold_to.startswith("-"):
            if sold_to not in contacts:
                contacts[sold_to] = str(uuid.uuid4())
            sold_contact_uuid = contacts[sold_to]
        
        # ---- Parse Ownership ----
        ownership_pct, ownership_notes = parse_ownership(ownership_raw)
        
        # ---- Clean Status ----
        status = STATUS_MAP.get(status_raw.strip() if status_raw else "", "available")
        
        # ---- Clean Currencies ----
        purchase_currency = clean_currency(currency_raw)
        expense_currency = clean_currency(expense_currency_raw)
        sale_currency = clean_currency(sale_currency_raw)
        
        # ---- Year ----
        year_str = None
        if year is not None:
            try:
                year_str = str(int(year))
            except (ValueError, TypeError):
                year_str = str(year)
        
        # ---- Build Artwork ----
        artwork_uuid = str(uuid.uuid4())
        artwork = {
            "id": artwork_uuid,
            "airtable_record_id": airtable_id,
            "inventory_number": str(ref_stag).strip() if ref_stag else None,
            "title": title,
            "artist_id": artist_uuid,
            "artist_ref": ref_artist.strip() if ref_artist else None,
            "year_created": year_str,
            "medium": medium.strip() if medium else None,
            "dimensions": dimensions.strip() if dimensions else None,
            "status": status,
            "location_id": location_uuid,
            "ownership_pct": ownership_pct,
            "ownership_notes": ownership_notes,
            "purchase_price": buy_price,
            "purchase_currency": purchase_currency,
            "purchase_date": date_bought,
            "acquired_from": acquired_from if acquired_from and acquired_contact_uuid else None,
            "current_value": est_value,
            "current_value_currency": "USD",
            "consignment_price": consignment_price,
            "consignment_currency": "USD",
            "total_expenses": expense_amount if expense_amount else 0,
            "expenses_currency": expense_currency,
            "cost_basis": stock_value,
            "cost_basis_currency": "USD",
            "provenance": provenance.strip() if provenance else None,
            "exhibition_history": exhibition_history.strip() if exhibition_history else None,
            "notes": comments.strip() if comments else None,
            "internal_notes": loic_instructions.strip() if loic_instructions else None,
            "remarks": remarks.strip() if remarks else None,
        }
        artworks.append(artwork)
        
        # ---- Build Purchase Transaction ----
        if buy_price and float(buy_price) > 0:
            transactions.append({
                "id": str(uuid.uuid4()),
                "artwork_id": artwork_uuid,
                "type": "purchase",
                "contact_id": acquired_contact_uuid,
                "amount": buy_price,
                "currency": purchase_currency,
                "date": date_bought or None,
                "notes": f"Imported from Airtable ({source_table})",
            })
        
        # ---- Build Expense (if any) ----
        if expense_amount and float(expense_amount) > 0:
            expenses_list.append({
                "id": str(uuid.uuid4()),
                "artwork_id": artwork_uuid,
                "category": "other",
                "description": f"Imported expenses: {remarks}" if remarks else "Imported expenses from Airtable",
                "amount": expense_amount,
                "currency": expense_currency,
                "date": date_bought or None,
            })
        
        # ---- Build Sale Transaction ----
        if sale_price and float(sale_price) > 0:
            transactions.append({
                "id": str(uuid.uuid4()),
                "artwork_id": artwork_uuid,
                "type": "sale",
                "contact_id": sold_contact_uuid,
                "amount": sale_price,
                "currency": sale_currency,
                "date": sale_date or None,
                "funds_received_date": funds_received or None,
                "profit_amount": profit_usd,
                "profit_currency": "USD",
                "notes": f"Sold to: {sold_to}" if sold_to else None,
            })
        
        # ---- Build Images ----
        if pictures:
            for i, pic in enumerate(pictures or []):
                images.append({
                    "id": str(uuid.uuid4()),
                    "artwork_id": artwork_uuid,
                    "url": pic.get("url", ""),
                    "filename": pic.get("filename", ""),
                    "mime_type": pic.get("type", ""),
                    "size_bytes": pic.get("size"),
                    "width_px": pic.get("width"),
                    "height_px": pic.get("height"),
                    "is_primary": i == 0,
                    "sort_order": i,
                    "original_url": pic.get("url", ""),
                })
        
        # ---- Build Documents (PDFs) ----
        if pdfs:
            for pdf in pdfs or []:
                documents.append({
                    "id": str(uuid.uuid4()),
                    "artwork_id": artwork_uuid,
                    "type": "factsheet",
                    "name": pdf.get("filename", "Document"),
                    "url": pdf.get("url", ""),
                    "storage_path": f"migrated/{airtable_id}/{pdf.get('filename', 'doc')}",
                    "mime_type": pdf.get("type", ""),
                    "size_bytes": pdf.get("size"),
                    "original_url": pdf.get("url", ""),
                })
        
        # ---- CSV row ----
        csv_rows.append({
            "airtable_id": airtable_id,
            "source": source_table,
            "title": title,
            "artist": artist_name or "",
            "status": status,
            "purchase_price": buy_price or "",
            "currency": purchase_currency,
            "location": loc_name or "",
            "sale_price": sale_price or "",
            "ownership": f"{ownership_pct}%",
        })
    
    # Process all records
    print("Processing Stock records...")
    for rec in stock_records:
        process_record(rec, "Stock")
    
    print("Processing Vendu records...")
    for rec in vendu_records:
        process_record(rec, "Vendu")
    
    print(f"\nMigration summary:")
    print(f"  Artists:      {len(artists)}")
    print(f"  Locations:    {len(locations)}")
    print(f"  Contacts:     {len(contacts)}")
    print(f"  Artworks:     {len(artworks)}")
    print(f"  Transactions: {len(transactions)}")
    print(f"  Expenses:     {len(expenses_list)}")
    print(f"  Images:       {len(images)}")
    print(f"  Documents:    {len(documents)}")
    print(f"  Issues:       {len(issues)}")
    
    # ---- Generate SQL ----
    print(f"\nGenerating SQL...")
    sql_lines = []
    sql_lines.append(f"-- =============================================================================")
    sql_lines.append(f"-- AIRTABLE MIGRATION DATA — Generated {datetime.now().isoformat()}")
    sql_lines.append(f"-- Records: {len(artworks)} artworks from {len(stock_records)} Stock + {len(vendu_records)} Vendu")
    sql_lines.append(f"-- =============================================================================")
    sql_lines.append(f"")
    sql_lines.append(f"-- SET YOUR TENANT ID (Clerk org_id)")
    sql_lines.append(f"\\set tenant_id '{tenant_id}'")
    sql_lines.append(f"")
    
    # Tenant
    sql_lines.append(f"-- Tenant")
    sql_lines.append(f"INSERT INTO tenants (id, name, slug, default_currency) VALUES ({sql_str(tenant_id)}, 'Stagadon', 'stagadon', 'USD') ON CONFLICT (id) DO NOTHING;")
    sql_lines.append(f"")
    
    # Artists
    sql_lines.append(f"-- Artists ({len(artists)})")
    for name, uid in sorted(artists.items()):
        sql_lines.append(
            f"INSERT INTO artists (id, tenant_id, name) "
            f"VALUES ('{uid}', {sql_str(tenant_id)}, {sql_str(name)}) "
            f"ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Locations
    sql_lines.append(f"-- Locations ({len(locations)})")
    for name, uid in sorted(locations.items()):
        sql_lines.append(
            f"INSERT INTO locations (id, tenant_id, name, country) "
            f"VALUES ('{uid}', {sql_str(tenant_id)}, {sql_str(name)}, 'US') "
            f"ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Contacts
    sql_lines.append(f"-- Contacts ({len(contacts)})")
    for name, uid in sorted(contacts.items()):
        ctype = guess_contact_type(name)
        sql_lines.append(
            f"INSERT INTO contacts (id, tenant_id, type, name) "
            f"VALUES ('{uid}', {sql_str(tenant_id)}, '{ctype}', {sql_str(name)}) "
            f"ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Artworks
    sql_lines.append(f"-- Artworks ({len(artworks)})")
    for a in artworks:
        sql_lines.append(
            f"INSERT INTO artworks ("
            f"id, tenant_id, inventory_number, title, artist_id, artist_ref, "
            f"year_created, medium, dimensions, status, location_id, "
            f"ownership_pct, ownership_notes, "
            f"purchase_price, purchase_currency, purchase_date, acquired_from, "
            f"current_value, current_value_currency, "
            f"consignment_price, consignment_currency, "
            f"total_expenses, expenses_currency, cost_basis, cost_basis_currency, "
            f"provenance, exhibition_history, notes, internal_notes, remarks, "
            f"airtable_record_id"
            f") VALUES ("
            f"'{a['id']}', {sql_str(tenant_id)}, {sql_str(a['inventory_number'])}, {sql_str(a['title'])}, "
            f"{'NULL' if not a['artist_id'] else sql_str(a['artist_id'])}, {sql_str(a['artist_ref'])}, "
            f"{sql_str(a['year_created'])}, {sql_str(a['medium'])}, {sql_str(a['dimensions'])}, "
            f"'{a['status']}', "
            f"{'NULL' if not a['location_id'] else sql_str(a['location_id'])}, "
            f"{sql_num(a['ownership_pct'])}, {sql_str(a['ownership_notes'])}, "
            f"{sql_num(a['purchase_price'])}, '{a['purchase_currency']}', {sql_date(a['purchase_date'])}, {sql_str(a['acquired_from'])}, "
            f"{sql_num(a['current_value'])}, '{a['current_value_currency']}', "
            f"{sql_num(a['consignment_price'])}, '{a['consignment_currency']}', "
            f"{sql_num(a['total_expenses'])}, '{a['expenses_currency']}', "
            f"{sql_num(a['cost_basis'])}, '{a['cost_basis_currency']}', "
            f"{sql_str(a['provenance'])}, {sql_str(a['exhibition_history'])}, "
            f"{sql_str(a['notes'])}, {sql_str(a['internal_notes'])}, {sql_str(a['remarks'])}, "
            f"{sql_str(a['airtable_record_id'])}"
            f") ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Transactions
    sql_lines.append(f"-- Transactions ({len(transactions)})")
    for t in transactions:
        sql_lines.append(
            f"INSERT INTO transactions ("
            f"id, tenant_id, artwork_id, type, contact_id, amount, currency, date, "
            f"funds_received_date, profit_amount, profit_currency, notes"
            f") VALUES ("
            f"'{t['id']}', {sql_str(tenant_id)}, '{t['artwork_id']}', '{t['type']}', "
            f"{'NULL' if not t.get('contact_id') else sql_str(t['contact_id'])}, "
            f"{sql_num(t['amount'])}, '{t['currency']}', {sql_date(t.get('date'))}, "
            f"{sql_date(t.get('funds_received_date'))}, "
            f"{sql_num(t.get('profit_amount'))}, "
            f"{'NULL' if not t.get('profit_currency') else sql_str(t['profit_currency'])}, "
            f"{sql_str(t.get('notes'))}"
            f") ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Expenses
    sql_lines.append(f"-- Expenses ({len(expenses_list)})")
    for e in expenses_list:
        sql_lines.append(
            f"INSERT INTO expenses ("
            f"id, tenant_id, artwork_id, category, description, amount, currency, date"
            f") VALUES ("
            f"'{e['id']}', {sql_str(tenant_id)}, '{e['artwork_id']}', '{e['category']}', "
            f"{sql_str(e['description'])}, {sql_num(e['amount'])}, '{e['currency']}', "
            f"{sql_date(e.get('date'))}"
            f") ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Images (reference only — actual files need to be migrated to Supabase Storage)
    sql_lines.append(f"-- Artwork Images ({len(images)}) — URLs are Airtable CDN, need storage migration")
    for img in images:
        sql_lines.append(
            f"INSERT INTO artwork_images ("
            f"id, tenant_id, artwork_id, storage_path, url, filename, mime_type, "
            f"size_bytes, width_px, height_px, is_primary, sort_order, original_url"
            f") VALUES ("
            f"'{img['id']}', {sql_str(tenant_id)}, '{img['artwork_id']}', "
            f"{sql_str('migrated/' + img['artwork_id'] + '/' + img['filename'])}, "
            f"{sql_str(img['url'])}, {sql_str(img['filename'])}, {sql_str(img['mime_type'])}, "
            f"{sql_num(img.get('size_bytes'))}, {sql_num(img.get('width_px'))}, {sql_num(img.get('height_px'))}, "
            f"{sql_bool(img['is_primary'])}, {img['sort_order']}, {sql_str(img['original_url'])}"
            f") ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    # Documents
    sql_lines.append(f"-- Documents ({len(documents)}) — URLs are Airtable CDN, need storage migration")
    for doc in documents:
        sql_lines.append(
            f"INSERT INTO documents ("
            f"id, tenant_id, artwork_id, type, name, storage_path, url, mime_type, "
            f"size_bytes, original_url"
            f") VALUES ("
            f"'{doc['id']}', {sql_str(tenant_id)}, '{doc['artwork_id']}', '{doc['type']}', "
            f"{sql_str(doc['name'])}, {sql_str(doc['storage_path'])}, {sql_str(doc['url'])}, "
            f"{sql_str(doc['mime_type'])}, {sql_num(doc.get('size_bytes'))}, "
            f"{sql_str(doc['original_url'])}"
            f") ON CONFLICT DO NOTHING;"
        )
    sql_lines.append(f"")
    
    sql_lines.append(f"-- Migration complete!")
    sql_lines.append(f"-- Total: {len(artworks)} artworks, {len(transactions)} transactions, "
                     f"{len(expenses_list)} expenses, {len(images)} images, {len(documents)} documents")
    
    # Write SQL
    with open(OUTPUT_SQL, "w") as f:
        f.write("\n".join(sql_lines))
    print(f"  → {OUTPUT_SQL} ({len(sql_lines)} lines)")
    
    # Write CSV summary
    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "airtable_id", "source", "title", "artist", "status",
            "purchase_price", "currency", "location", "sale_price", "ownership"
        ])
        writer.writeheader()
        writer.writerows(csv_rows)
    print(f"  → {OUTPUT_CSV} ({len(csv_rows)} rows)")
    
    # Write report
    report_lines = [
        f"# Migration Report",
        f"**Generated:** {datetime.now().isoformat()}",
        f"**Tenant ID:** `{tenant_id}`",
        f"",
        f"## Summary",
        f"| Entity | Count |",
        f"|--------|-------|",
        f"| Artists | {len(artists)} |",
        f"| Locations | {len(locations)} |",
        f"| Contacts | {len(contacts)} |",
        f"| Artworks | {len(artworks)} |",
        f"| Transactions | {len(transactions)} |",
        f"| Expenses | {len(expenses_list)} |",
        f"| Images | {len(images)} |",
        f"| Documents | {len(documents)} |",
        f"",
        f"## Source Breakdown",
        f"- Stock table: {len(stock_records)} records → {len([a for a in artworks if a['airtable_record_id'].startswith('rec')])} artworks",
        f"- Vendu table: {len(vendu_records)} records",
        f"",
        f"## Data Quality Issues ({len(issues)})",
    ]
    for issue in issues:
        report_lines.append(f"- {issue}")
    
    report_lines.extend([
        f"",
        f"## Important Notes",
        f"",
        f"### Image Migration",
        f"The artwork_images and documents tables contain Airtable CDN URLs in the `url` and `original_url` columns.",
        f"These URLs are temporary and will expire. You need to:",
        f"1. Download each image from the Airtable URL",
        f"2. Upload to Supabase Storage (artwork-images bucket)",
        f"3. Update the `storage_path` and `url` columns with the new Supabase paths",
        f"",
        f"A separate image migration script can handle this when you're ready for production.",
        f"",
        f"### Vendu Table Overlap",
        f"Some records may exist in both Stock and Vendu tables.",
        f"The migration deduplicates by Airtable record ID, but since the tables have different IDs,",
        f"you may have duplicates that need manual cleanup (same artwork, different record IDs).",
        f"",
        f"### Currency Notes",
        f"- All profit/P&L values are stored in USD (matching your Airtable convention)",
        f"- Purchase prices are in the original currency as specified per record",
        f"- The Airtable Currency/Currency Expenses fields had data corruption (dollar amounts in select fields)",
        f"  — these have been cleaned during migration",
    ])
    
    with open(OUTPUT_REPORT, "w") as f:
        f.write("\n".join(report_lines))
    print(f"  → {OUTPUT_REPORT}")
    
    print(f"\nDone! Review the files in {MIGRATION_DIR}/")
    print(f"To import: paste migration_data.sql into Supabase SQL Editor")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Migrate Airtable to Supabase")
    parser.add_argument("--tenant-id", default="YOUR_TENANT_ID",
                        help="Your Clerk Organization ID")
    args = parser.parse_args()
    migrate(args.tenant_id)
