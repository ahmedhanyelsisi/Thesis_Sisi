import urllib.request
import json
import ssl

url = 'https://ahmedelsisi.pythonanywhere.com/api/data'
file_path = r'D:\Masters\Thesis_Repo\Thesis_Sisi\Dashboard\dashboard_data.json'

print(f"Reading {file_path}...")
with open(file_path, 'rb') as f:
    data = f.read()

print(f"Uploading {len(data) / (1024*1024):.2f} MB to {url}...")
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})

try:
    context = ssl._create_unverified_context()
    with urllib.request.urlopen(req, context=context) as response:
        print("Status code:", response.getcode())
        print("Response:", response.read().decode('utf-8'))
except Exception as e:
    print("Error:", e)
    if hasattr(e, 'read'):
        print(e.read().decode('utf-8'))
