# PetLift

Community transport coordination platform for Phoenix rescue animals.

## Features

- **User Authentication**: Secure registration and login with Supabase Auth
- **Role-Based Access**: Separate dashboards for rescuers and drivers
- **Transport Requests**: Rescuers can post transport needs with detailed information
- **Trip Management**: Drivers can claim requests and update trip status in real-time
- **Contact Coordination**: Automatic sharing of contact info between rescuers and drivers
- **Mobile-Responsive**: Optimized for mobile devices

## Technology Stack

- **Backend**: Python Flask
- **Database**: Supabase (PostgreSQL)
- **Authentication**: Supabase Auth
- **Frontend**: Server-side rendered templates with enhanced CSS

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure environment variables in `.env`:
```
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_SUPABASE_ANON_KEY=your_supabase_anon_key
SECRET_KEY=your_secret_key
```

3. The database schema is already applied via Supabase migrations

4. Run the application:
```bash
python app.py
```

## Database Schema

- **profiles**: User accounts with role and vehicle information
- **transport_requests**: Transport needs posted by rescuers
- **trips**: Active trips claimed by drivers
- **trip_updates**: Status update history for trips

## Security

- Row Level Security (RLS) enabled on all tables
- User data protected by authentication policies
- Secure session management
- Input validation and error handling

## Usage

### For Rescuers
1. Register an account with "Rescuer" role
2. Create transport requests with pickup/dropoff details
3. Track the status of your requests
4. View driver contact information when trip is claimed

### For Drivers
1. Register with "Driver" or "Both" role
2. View available transport requests
3. Claim trips that fit your schedule
4. Update trip status as you progress
5. Contact rescuers directly through provided information

## License

MIT
