import os
from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
from supabase import create_client, Client
from dotenv import load_dotenv
from functools import wraps

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "petlift-dev-secret-key")

supabase_url = os.getenv("VITE_SUPABASE_URL")
supabase_key = os.getenv("VITE_SUPABASE_SUPABASE_ANON_KEY")

if not supabase_url or not supabase_key:
    raise ValueError("Supabase credentials not found in environment variables")

supabase: Client = create_client(supabase_url, supabase_key)

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            flash("Please log in to access this page", "warning")
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def get_current_user():
    if 'user' not in session:
        return None
    return session['user']

@app.route("/")
def index():
    user = get_current_user()
    return render_template("index.html", user=user)

@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        try:
            email = request.form.get("email", "").strip()
            password = request.form.get("password", "").strip()
            full_name = request.form.get("full_name", "").strip()
            phone = request.form.get("phone", "").strip()
            role = request.form.get("role", "rescuer")
            has_vehicle = request.form.get("has_vehicle") == "on"
            vehicle_capacity = int(request.form.get("vehicle_capacity", 0))

            if not email or not password or not full_name:
                flash("Please fill in all required fields", "error")
                return render_template("register.html")

            if len(password) < 6:
                flash("Password must be at least 6 characters", "error")
                return render_template("register.html")

            auth_response = supabase.auth.sign_up({
                "email": email,
                "password": password
            })

            if auth_response.user:
                profile_data = {
                    "id": auth_response.user.id,
                    "full_name": full_name,
                    "phone": phone,
                    "role": role,
                    "has_vehicle": has_vehicle,
                    "vehicle_capacity": vehicle_capacity
                }

                supabase.table("profiles").insert(profile_data).execute()

                session['user'] = {
                    "id": auth_response.user.id,
                    "email": email,
                    "full_name": full_name,
                    "role": role
                }

                flash("Registration successful! Welcome to PetLift", "success")

                if role == "driver" or role == "both":
                    return redirect(url_for('driver_home'))
                else:
                    return redirect(url_for('rescuer_home'))
            else:
                flash("Registration failed. Please try again.", "error")

        except Exception as e:
            flash(f"An error occurred: {str(e)}", "error")

    return render_template("register.html")

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        try:
            email = request.form.get("email", "").strip()
            password = request.form.get("password", "").strip()

            if not email or not password:
                flash("Please enter both email and password", "error")
                return render_template("login.html")

            auth_response = supabase.auth.sign_in_with_password({
                "email": email,
                "password": password
            })

            if auth_response.user:
                profile = supabase.table("profiles").select("*").eq("id", auth_response.user.id).maybeSingle().execute()

                session['user'] = {
                    "id": auth_response.user.id,
                    "email": email,
                    "full_name": profile.data['full_name'],
                    "role": profile.data['role']
                }

                flash("Login successful!", "success")

                next_page = request.args.get('next')
                if next_page:
                    return redirect(next_page)

                if profile.data['role'] == "driver":
                    return redirect(url_for('driver_home'))
                else:
                    return redirect(url_for('rescuer_home'))
            else:
                flash("Invalid email or password", "error")

        except Exception as e:
            flash("Invalid email or password", "error")

    return render_template("login.html")

@app.route("/logout")
def logout():
    try:
        supabase.auth.sign_out()
    except:
        pass
    session.clear()
    flash("You have been logged out", "info")
    return redirect(url_for('index'))

@app.route("/rescuer", methods=["GET", "POST"])
@login_required
def rescuer_home():
    user = get_current_user()

    if request.method == "POST":
        try:
            pickup = request.form.get("pickup_loc", "").strip()
            clinic = request.form.get("dropoff_clinic", "").strip()
            crates = int(request.form.get("crate_count", 1))
            reason = request.form.get("reason", "Clinic visit")
            instructions = request.form.get("special_instructions", "").strip()

            if not pickup or not clinic:
                flash("Please fill in all required fields", "error")
            elif crates < 1 or crates > 20:
                flash("Crate count must be between 1 and 20", "error")
            else:
                request_data = {
                    "rescuer_id": user['id'],
                    "pickup_location": pickup,
                    "dropoff_clinic": clinic,
                    "crate_count": crates,
                    "reason": reason,
                    "special_instructions": instructions
                }

                supabase.table("transport_requests").insert(request_data).execute()
                flash("Transport request created successfully!", "success")
                return redirect(url_for('rescuer_home'))

        except Exception as e:
            flash(f"Error creating request: {str(e)}", "error")

    try:
        my_requests = supabase.table("transport_requests")\
            .select("*, trips(*)")\
            .eq("rescuer_id", user['id'])\
            .order("created_at", desc=True)\
            .execute()

        return render_template("rescuer_home.html",
                             requests=my_requests.data,
                             user=user)
    except Exception as e:
        flash(f"Error loading requests: {str(e)}", "error")
        return render_template("rescuer_home.html", requests=[], user=user)

@app.route("/driver")
@login_required
def driver_home():
    user = get_current_user()

    try:
        open_requests = supabase.table("transport_requests")\
            .select("*, profiles!transport_requests_rescuer_id_fkey(full_name, phone)")\
            .eq("status", "open")\
            .order("created_at", desc=False)\
            .execute()

        active_trips = supabase.table("trips")\
            .select("*, transport_requests(*, profiles!transport_requests_rescuer_id_fkey(full_name, phone))")\
            .eq("driver_id", user['id'])\
            .neq("status", "completed")\
            .order("created_at", desc=True)\
            .execute()

        return render_template("driver_home.html",
                             open_requests=open_requests.data,
                             active_trips=active_trips.data,
                             user=user)
    except Exception as e:
        flash(f"Error loading trips: {str(e)}", "error")
        return render_template("driver_home.html",
                             open_requests=[],
                             active_trips=[],
                             user=user)

@app.route("/driver/claim/<request_id>", methods=["POST"])
@login_required
def claim_request(request_id):
    user = get_current_user()

    try:
        trip_data = {
            "request_id": request_id,
            "driver_id": user['id'],
            "status": "scheduled"
        }

        supabase.table("trips").insert(trip_data).execute()

        supabase.table("transport_requests")\
            .update({"status": "claimed"})\
            .eq("id", request_id)\
            .execute()

        flash("Trip claimed successfully!", "success")
    except Exception as e:
        flash(f"Error claiming trip: {str(e)}", "error")

    return redirect(url_for("driver_home"))

@app.route("/trip/<trip_id>/status", methods=["POST"])
@login_required
def update_trip_status(trip_id):
    user = get_current_user()

    try:
        new_status = request.form.get("status")
        message = request.form.get("message", "")

        update_data = {"status": new_status}

        if new_status == "picked_up" and message:
            update_data["started_at"] = "now()"
        elif new_status == "completed":
            update_data["completed_at"] = "now()"

        supabase.table("trips")\
            .update(update_data)\
            .eq("id", trip_id)\
            .eq("driver_id", user['id'])\
            .execute()

        trip_update = {
            "trip_id": trip_id,
            "driver_id": user['id'],
            "status": new_status,
            "message": message
        }
        supabase.table("trip_updates").insert(trip_update).execute()

        if new_status == "completed":
            trip = supabase.table("trips").select("request_id").eq("id", trip_id).maybeSingle().execute()
            supabase.table("transport_requests")\
                .update({"status": "completed"})\
                .eq("id", trip.data['request_id'])\
                .execute()

        flash("Trip status updated!", "success")
    except Exception as e:
        flash(f"Error updating trip: {str(e)}", "error")

    return redirect(url_for("driver_home"))

@app.route("/profile")
@login_required
def profile():
    user = get_current_user()

    try:
        profile_data = supabase.table("profiles")\
            .select("*")\
            .eq("id", user['id'])\
            .maybeSingle()\
            .execute()

        return render_template("profile.html", profile=profile_data.data, user=user)
    except Exception as e:
        flash(f"Error loading profile: {str(e)}", "error")
        return redirect(url_for('index'))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
