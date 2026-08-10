-- 011_add_driver_fields.sql
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS driver VARCHAR(100);
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS odometer DECIMAL(12,2);
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS fuel_level DECIMAL(5,2);
