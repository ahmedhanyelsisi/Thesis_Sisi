from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import json
import os

app = Flask(__name__, static_folder='static')
CORS(app)  # Enable CORS for all routes

DATA_FILE = os.path.join(os.path.dirname(__file__), 'data', 'dashboard_data.json')

def load_data():
    if not os.path.exists(DATA_FILE):
        return None
    try:
        with open(DATA_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading data: {e}")
        return None

def save_data(data):
    try:
        # Ensure directory exists
        os.makedirs(os.path.dirname(DATA_FILE), exist_ok=True)
        with open(DATA_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f)
        return True
    except Exception as e:
        print(f"Error saving data: {e}")
        return False

@app.route('/')
def index():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/api/data', methods=['GET'])
def get_data():
    data = load_data()
    if data is None:
        return jsonify({"status": "empty", "data": None}), 200
    return jsonify({"status": "success", "data": data}), 200

@app.route('/api/data', methods=['POST'])
def post_data():
    new_data = request.json
    if not new_data:
        return jsonify({"error": "No data provided"}), 400
    
    success = save_data(new_data)
    if success:
        return jsonify({"status": "success"}), 200
    else:
        return jsonify({"error": "Failed to save data"}), 500

if __name__ == '__main__':
    # Use port 5000 for local development
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True)
