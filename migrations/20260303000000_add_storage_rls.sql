-- Migration: Storage RLS policies for the clips bucket.
-- Without this, authenticated users cannot call createSignedUrl because
-- storage.objects has RLS enabled by default and no policies were defined.

-- Allow authenticated users to read (and create signed URLs for) clips that
-- belong to a camera in their org. The clip path format is
-- {camera_uuid}/{timestamp}.mp4, so the first folder segment is the camera UUID.
CREATE POLICY "org_scoped_clip_read" ON storage.objects
    FOR SELECT
    USING (
        bucket_id = 'clips'
        AND auth.role() = 'authenticated'
        AND (storage.foldername(name))[1] IN (
            SELECT id::text FROM cameras WHERE org_id = public.user_org_id()
        )
    );
