DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE violations;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE cameras;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
