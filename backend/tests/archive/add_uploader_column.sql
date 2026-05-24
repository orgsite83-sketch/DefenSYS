-- Add is_uploader column to the user table
ALTER TABLE authentication_access_control_user 
ADD COLUMN is_uploader BOOLEAN DEFAULT FALSE NOT NULL;

-- Update the migration record
INSERT INTO django_migrations (app, name, applied) 
VALUES ('authentication_access_control', '0002_user_is_uploader', CURRENT_TIMESTAMP);
