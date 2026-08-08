import re
import base64
import io
from PIL import Image

def process_html(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        html = f.read()

    print("Fixing duplicate exportSnapshot code...")
    # Remove the first, buggy exportSnapshot function
    script_fix = re.sub(
        r'function exportSnapshot\(\) \{\s*// Update DOM to reflect current selections.*?URL\.revokeObjectURL\(url\);\s*\}', 
        '', html, flags=re.DOTALL
    )
    # Remove the extra brace right before the second exportSnapshot
    script_fix = re.sub(
        r'\}\s*\}\s*function exportSnapshot\(\)',
        '}\n\n        function exportSnapshot()',
        script_fix
    )
    
    html = script_fix

    # Regex to find base64 images
    pattern = re.compile(r'data:image/(png|jpeg|jpg);base64,([A-Za-z0-9+/=]+)')

    def replace_image(match):
        ext = match.group(1)
        b64_data = match.group(2)
        try:
            image_data = base64.b64decode(b64_data)
            img = Image.open(io.BytesIO(image_data))
            
            # Convert to WebP
            output = io.BytesIO()
            img.save(output, format='WebP', quality=60, method=4)
            webp_data = output.getvalue()
            
            new_b64 = base64.b64encode(webp_data).decode('utf-8')
            return f"data:image/webp;base64,{new_b64}"
        except Exception as e:
            print(f"Error converting image: {e}")
            return match.group(0)

    print("Starting compression (this might take a minute)...")
    new_html = pattern.sub(replace_image, html)
    
    print(f"Original size: {len(html) / 1024 / 1024:.2f} MB")
    print(f"New size: {len(new_html) / 1024 / 1024:.2f} MB")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_html)
    print("Done processing HTML!")

process_html('D:/Masters/Thesis_Repo/Thesis_Sisi/Dashboard/Paper_Test_Cases_Dashboard_V2.html')
