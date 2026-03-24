/*
  # PetLift Database Schema

  ## Overview
  Creates the complete database schema for PetLift, a community pet transport coordination platform.

  ## New Tables
  
  ### 1. profiles
  - `id` (uuid, FK to auth.users) - User identifier
  - `full_name` (text) - User's full name
  - `phone` (text) - Contact phone number
  - `role` (text) - User role: rescuer, driver, or both
  - `has_vehicle` (boolean) - Whether user has a vehicle available
  - `vehicle_capacity` (integer) - Number of crates vehicle can hold
  - `created_at` (timestamptz) - Account creation timestamp
  - `updated_at` (timestamptz) - Last profile update
  
  ### 2. transport_requests
  - `id` (uuid, PK) - Request identifier
  - `rescuer_id` (uuid, FK) - Rescuer who created request
  - `pickup_location` (text) - Pickup address/neighborhood
  - `dropoff_clinic` (text) - Destination clinic name
  - `crate_count` (integer) - Number of animal crates
  - `reason` (text) - Purpose of transport
  - `special_instructions` (text) - Additional notes
  - `status` (text) - open, claimed, in_transit, completed, cancelled
  - `created_at` (timestamptz) - Request creation time
  - `updated_at` (timestamptz) - Last status update
  
  ### 3. trips
  - `id` (uuid, PK) - Trip identifier
  - `request_id` (uuid, FK) - Associated transport request
  - `driver_id` (uuid, FK) - Driver who claimed trip
  - `status` (text) - scheduled, picked_up, in_transit, at_clinic, completed
  - `claimed_at` (timestamptz) - When driver claimed
  - `started_at` (timestamptz) - When pickup occurred
  - `completed_at` (timestamptz) - When trip finished
  - `created_at` (timestamptz) - Trip creation time
  
  ### 4. trip_updates
  - `id` (uuid, PK) - Update identifier
  - `trip_id` (uuid, FK) - Associated trip
  - `driver_id` (uuid, FK) - Driver posting update
  - `status` (text) - Trip status at time of update
  - `message` (text) - Optional status message
  - `created_at` (timestamptz) - Update timestamp

  ## Security
  - RLS enabled on all tables
  - Profiles: Users can read all, update only their own
  - Transport requests: Rescuers create/view own; drivers view open requests
  - Trips: Drivers manage their own trips; rescuers view their request's trip
  - Trip updates: Drivers create for their trips; rescuers view for their requests

  ## Important Notes
  1. All timestamps use timestamptz for timezone awareness
  2. Foreign keys ensure data integrity
  3. Indexes on frequently queried columns for performance
  4. Default values prevent null issues
*/

-- Create profiles table
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text,
  role text NOT NULL DEFAULT 'rescuer' CHECK (role IN ('rescuer', 'driver', 'both')),
  has_vehicle boolean NOT NULL DEFAULT false,
  vehicle_capacity integer DEFAULT 0 CHECK (vehicle_capacity >= 0),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create transport_requests table
CREATE TABLE IF NOT EXISTS transport_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rescuer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  pickup_location text NOT NULL,
  dropoff_clinic text NOT NULL,
  crate_count integer NOT NULL CHECK (crate_count > 0),
  reason text NOT NULL DEFAULT 'Clinic visit',
  special_instructions text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'claimed', 'in_transit', 'completed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE transport_requests ENABLE ROW LEVEL SECURITY;

-- Create trips table
CREATE TABLE IF NOT EXISTS trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES transport_requests(id) ON DELETE CASCADE,
  driver_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'picked_up', 'in_transit', 'at_clinic', 'completed')),
  claimed_at timestamptz DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;

-- Create trip_updates table
CREATE TABLE IF NOT EXISTS trip_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  driver_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL,
  message text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE trip_updates ENABLE ROW LEVEL SECURITY;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_transport_requests_rescuer ON transport_requests(rescuer_id);
CREATE INDEX IF NOT EXISTS idx_transport_requests_status ON transport_requests(status);
CREATE INDEX IF NOT EXISTS idx_trips_request ON trips(request_id);
CREATE INDEX IF NOT EXISTS idx_trips_driver ON trips(driver_id);
CREATE INDEX IF NOT EXISTS idx_trip_updates_trip ON trip_updates(trip_id);

-- RLS Policies for profiles
CREATE POLICY "Users can view all profiles"
  ON profiles FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- RLS Policies for transport_requests
CREATE POLICY "Authenticated users can view open requests"
  ON transport_requests FOR SELECT
  TO authenticated
  USING (status = 'open' OR rescuer_id = auth.uid());

CREATE POLICY "Rescuers can create requests"
  ON transport_requests FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = rescuer_id);

CREATE POLICY "Rescuers can update own requests"
  ON transport_requests FOR UPDATE
  TO authenticated
  USING (auth.uid() = rescuer_id)
  WITH CHECK (auth.uid() = rescuer_id);

-- RLS Policies for trips
CREATE POLICY "Drivers and rescuers can view relevant trips"
  ON trips FOR SELECT
  TO authenticated
  USING (
    auth.uid() = driver_id OR
    EXISTS (
      SELECT 1 FROM transport_requests
      WHERE transport_requests.id = trips.request_id
      AND transport_requests.rescuer_id = auth.uid()
    )
  );

CREATE POLICY "Drivers can create trips"
  ON trips FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "Drivers can update own trips"
  ON trips FOR UPDATE
  TO authenticated
  USING (auth.uid() = driver_id)
  WITH CHECK (auth.uid() = driver_id);

-- RLS Policies for trip_updates
CREATE POLICY "Users can view updates for relevant trips"
  ON trip_updates FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM trips
      WHERE trips.id = trip_updates.trip_id
      AND (
        trips.driver_id = auth.uid() OR
        EXISTS (
          SELECT 1 FROM transport_requests
          WHERE transport_requests.id = trips.request_id
          AND transport_requests.rescuer_id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Drivers can create trip updates"
  ON trip_updates FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = driver_id);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_transport_requests_updated_at ON transport_requests;
CREATE TRIGGER update_transport_requests_updated_at
  BEFORE UPDATE ON transport_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();