INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  (
    'polls-images', 'polls-images', true, 
    5242880, 
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif']::text[]
  ),
  (
    'restaurant_menu', 'restaurant_menu', true, 
    5242880, 
    NULL -- "Any"
  ),
  (
    'promotions_images', 'promotions_images', true, 
    5242880, 
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']::text[]
  ),
  (
    'articles', 'articles', true, 
    NULL, -- "Unset"
    NULL  -- "Any"
  ),
  (
    'member-card', 'member-card', true, 
    NULL, 
    NULL
  ),
  (
    'restaurants-images', 'restaurants-images', true, 
    NULL, 
    NULL
  ),
  (
    'offers-images', 'offers-images', true, 
    NULL, 
    NULL
  )
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;