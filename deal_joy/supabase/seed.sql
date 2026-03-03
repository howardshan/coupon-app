-- =============================================================
-- DealJoy Seed Data
-- Run AFTER schema.sql (supabase/migrations/20260228000000_initial_schema.sql)
-- NOTE: This file is for reference. Seed was originally applied via REST API.
--       To re-run on a fresh DB, first create a user via Supabase Auth Admin API
--       and replace USER_ID below with the returned UUID.
-- =============================================================

-- Step 1: Create seed user via Supabase Auth Admin API (run once, outside SQL)
--   POST https://<project_ref>.supabase.co/auth/v1/admin/users
--   Body: { "email": "merchant@dealjoy.com", "password": "Dealjoy2024x", "email_confirm": true }
--   → Save the returned "id" as USER_ID

-- Step 2: Replace USER_ID below and run this SQL in Supabase SQL Editor

DO $$
DECLARE
  user_id UUID := '3c48d3eb-1fb6-419d-81d5-aa56ab4cc0e4'; -- merchant@dealjoy.com
  merchant1_id UUID;
  merchant2_id UUID;
  merchant3_id UUID;
  expires TIMESTAMPTZ := '2027-12-31 23:59:59+00';
BEGIN

-- ── Merchants ──────────────────────────────────────────────────
INSERT INTO public.merchants (user_id, name, description, logo_url, address, lat, lng, phone, status)
VALUES (
  user_id,
  'Texas BBQ House',
  'Authentic Texas-style BBQ with slow-smoked meats and classic sides.',
  'https://images.unsplash.com/photo-1544025162-d76694265947?w=400',
  '2301 N Henderson Ave, Dallas, TX 75206',
  32.8210, -96.7793,
  '+1-214-555-0101',
  'approved'
) RETURNING id INTO merchant1_id;

INSERT INTO public.merchants (user_id, name, description, logo_url, address, lat, lng, phone, status)
VALUES (
  user_id,
  'Hot Pot Paradise',
  'Premium hot pot with fresh ingredients and 8 different broth options.',
  'https://images.unsplash.com/photo-1569050467447-ce54b3bbc37d?w=400',
  '4601 W Park Blvd, Plano, TX 75093',
  33.0198, -96.7497,
  '+1-469-555-0202',
  'approved'
) RETURNING id INTO merchant2_id;

INSERT INTO public.merchants (user_id, name, description, logo_url, address, lat, lng, phone, status)
VALUES (
  user_id,
  'Sakura Sushi Bar',
  'Fresh sushi and authentic Japanese cuisine in the heart of Dallas.',
  'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=400',
  '3636 McKinney Ave, Dallas, TX 75204',
  32.8090, -96.8001,
  '+1-214-555-0303',
  'approved'
) RETURNING id INTO merchant3_id;

-- ── Deals ──────────────────────────────────────────────────────
INSERT INTO public.deals (merchant_id, title, description, category, original_price, discount_price,
  discount_label, image_urls, dishes, merchant_hours, stock_limit, total_sold, rating, review_count,
  is_featured, is_active, refund_policy, expires_at, address, lat, lng)
VALUES
  (merchant1_id,
   'BBQ Feast for 2 — Brisket + Ribs + Sides',
   'Slow-smoked beef brisket, baby back ribs, coleslaw, baked beans, and cornbread.',
   'BBQ', 89.00, 49.00, '45% OFF',
   ARRAY['https://images.unsplash.com/photo-1544025162-d76694265947?w=800',
         'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=800'],
   '["Beef Brisket (1lb)", "Baby Back Ribs (half rack)", "Coleslaw", "Baked Beans", "Cornbread"]',
   'Mon–Sun 11:00 AM – 10:00 PM', 50, 127, 4.80, 89, true, true,
   'Risk-Free Refund within 7 days', expires,
   '2301 N Henderson Ave, Dallas, TX 75206', 32.8210, -96.7793),

  (merchant1_id,
   'BBQ Sampler Platter',
   'Taste everything: brisket, pulled pork, sausage, and three sides.',
   'BBQ', 55.00, 32.00, '40% OFF',
   ARRAY['https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=800'],
   '["Brisket (4oz)", "Pulled Pork (4oz)", "Jalapeño Sausage", "2 Sides of Choice"]',
   'Mon–Sun 11:00 AM – 10:00 PM', 30, 55, 4.60, 42, false, true,
   'Risk-Free Refund within 7 days', expires,
   '2301 N Henderson Ave, Dallas, TX 75206', 32.8210, -96.7793),

  (merchant2_id,
   'Hot Pot Premium Set for 2',
   'Everything you need for the perfect hot pot experience.',
   'Hot Pot', 78.00, 45.00, '42% OFF',
   ARRAY['https://images.unsplash.com/photo-1569050467447-ce54b3bbc37d?w=800',
         'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=800'],
   '["Wagyu Beef (200g)", "Pork Belly (200g)", "Mushroom Mix", "Tofu Plate", "Noodles", "Dipping Sauce Set"]',
   'Mon–Sun 11:00 AM – 11:00 PM', 40, 213, 4.90, 156, true, true,
   'Risk-Free Refund within 7 days', expires,
   '4601 W Park Blvd, Plano, TX 75093', 33.0198, -96.7497),

  (merchant2_id,
   'Spicy Mala Hot Pot Solo Set',
   'Individual hot pot with our famous mala spicy broth.',
   'Hot Pot', 38.00, 22.00, 'BUY 1 GET 1',
   ARRAY['https://images.unsplash.com/photo-1585032226651-759b368d7246?w=800'],
   '["Mala Broth (spicy level selectable)", "Beef Slices (150g)", "Veggies Mix", "Noodles"]',
   'Mon–Sun 11:00 AM – 11:00 PM', 60, 88, 4.70, 63, false, true,
   'Risk-Free Refund within 7 days', expires,
   '4601 W Park Blvd, Plano, TX 75093', 33.0198, -96.7497),

  (merchant3_id,
   'Omakase Sushi Experience (8 Pieces)',
   'Chef''s selection of 8 premium nigiri pieces with miso soup and edamame.',
   'Sushi', 65.00, 39.00, '40% OFF',
   ARRAY['https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=800',
         'https://images.unsplash.com/photo-1617196034183-421b4040ed20?w=800'],
   '["8 Chef''s Choice Nigiri", "Miso Soup", "Edamame", "Pickled Ginger"]',
   'Tue–Sun 5:00 PM – 10:30 PM', 20, 174, 4.95, 201, true, true,
   'Risk-Free Refund within 7 days', expires,
   '3636 McKinney Ave, Dallas, TX 75204', 32.8090, -96.8001);

RAISE NOTICE 'Seed data inserted: merchant1=%, merchant2=%, merchant3=%', merchant1_id, merchant2_id, merchant3_id;
END $$;
