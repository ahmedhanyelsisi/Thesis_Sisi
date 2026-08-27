import requests
import websocket
import json
import sys
import argparse
import os

def get_prism_ws_url():
    try:
        response = requests.get('http://localhost:9222/json', timeout=2)
        tabs = response.json()
        for tab in tabs:
            if 'prism.openai.com' in tab.get('url', ''):
                return tab.get('webSocketDebuggerUrl')
        return None
    except Exception as e:
        print(f"Error connecting to Chrome: {e}", file=sys.stderr)
        return None

def evaluate_js(ws_url, expression):
    ws = websocket.create_connection(ws_url, suppress_origin=True)
    command = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True
        }
    }
    ws.send(json.dumps(command))
    result = ws.recv()
    ws.close()
    
    data = json.loads(result)
    if 'result' in data and 'result' in data['result']:
        return data['result']['result'].get('value', data['result']['result'])
    elif 'error' in data:
        print(f"JS Evaluation error: {data['error']}", file=sys.stderr)
        return None
    return data

def cmd_list(ws_url):
    js = """
    (function() {
        if (typeof monaco === 'undefined') return {error: "Monaco not found"};
        var models = monaco.editor.getModels();
        var files = [];
        for (var i = 0; i < models.length; i++) {
            var uri = models[i].uri.toString();
            files.push(uri);
        }
        return files;
    })()
    """
    files = evaluate_js(ws_url, js)
    if isinstance(files, dict) and 'error' in files:
        print(files['error'])
        return
    print("Files currently loaded in Prism memory:")
    for f in files:
        # Extract filename from URI if possible
        filename = f.split('/')[-1] if '/' in f else f
        print(f"- {filename}  (URI: {f})")

def cmd_active(ws_url):
    js = """
    (function() {
        if (typeof monaco === 'undefined') return {error: "Monaco not found"};
        var editors = monaco.editor.getEditors();
        for (var i = 0; i < editors.length; i++) {
            if (editors[i].hasTextFocus() || editors.length === 1 || i === 0) {
                return editors[i].getModel().getValue();
            }
        }
        return {error: "No active editor found."};
    })()
    """
    result = evaluate_js(ws_url, js)
    if isinstance(result, dict) and 'error' in result:
        print(result['error'], file=sys.stderr)
        sys.exit(1)
    else:
        print(result)

def cmd_write_active(ws_url, source_file):
    if not os.path.exists(source_file):
        print(f"Source file not found: {source_file}", file=sys.stderr)
        sys.exit(1)
        
    with open(source_file, 'r', encoding='utf-8') as f:
        content = f.read()
        
    content_js = json.dumps(content)
    
    js = f"""
    (function() {{
        if (typeof monaco === 'undefined') return {{error: "Monaco not found"}};
        var editors = monaco.editor.getEditors();
        var activeEditor = null;
        for (var i = 0; i < editors.length; i++) {{
            if (editors[i].hasTextFocus() || editors.length === 1 || i === 0) {{
                activeEditor = editors[i];
                break;
            }}
        }}
        
        if (activeEditor) {{
            var model = activeEditor.getModel();
            var range = model.getFullModelRange();
            activeEditor.executeEdits("AI_Agent", [{{
                range: range,
                text: {content_js},
                forceMoveMarkers: true
            }}]);
            return {{success: true}};
        }}
        return {{error: "No active editor found to write to."}};
    }})()
    """
    result = evaluate_js(ws_url, js)
    if isinstance(result, dict):
        if 'error' in result:
            print(result['error'], file=sys.stderr)
            sys.exit(1)
        elif result.get('success'):
            print(f"Successfully wrote {len(content)} characters to the active Prism editor!")
    else:
        print("Unexpected result:", result)

import subprocess

def cmd_apply_and_sync(ws_url, local_target_file, source_file):
    if not os.path.exists(source_file):
        print(f"Source file not found: {source_file}", file=sys.stderr)
        sys.exit(1)
        
    with open(source_file, 'r', encoding='utf-8') as f:
        content = f.read()
        
    content_js = json.dumps(content)
    
    # 1. Write to Prism Active Tab
    js = f"""
    (function() {{
        if (typeof monaco === 'undefined') return {{error: "Monaco not found"}};
        var editors = monaco.editor.getEditors();
        var activeEditor = null;
        for (var i = 0; i < editors.length; i++) {{
            if (editors[i].hasTextFocus() || editors.length === 1 || i === 0) {{
                activeEditor = editors[i];
                break;
            }}
        }}
        
        if (activeEditor) {{
            var model = activeEditor.getModel();
            var range = model.getFullModelRange();
            activeEditor.executeEdits("AI_Agent", [{{
                range: range,
                text: {content_js},
                forceMoveMarkers: true
            }}]);
            return {{success: true}};
        }}
        return {{error: "No active editor found to write to."}};
    }})()
    """
    result = evaluate_js(ws_url, js)
    if isinstance(result, dict) and 'error' in result:
        print(f"Prism update failed: {result['error']}", file=sys.stderr)
        sys.exit(1)
    elif isinstance(result, dict) and result.get('success'):
        print(f"[SUCCESS] Wrote {len(content)} characters to the active Prism editor!")
    else:
        print(f"Unexpected result from Prism: {result}")
        sys.exit(1)

    # 2. Save locally
    try:
        with open(local_target_file, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"[SUCCESS] Saved locally to {local_target_file}")
    except Exception as e:
        print(f"Failed to save locally: {e}", file=sys.stderr)
        sys.exit(1)
        
    # 3. Git Commit and Push
    print("[WAIT] Synchronizing with GitHub...")
    try:
        subprocess.run(["git", "add", local_target_file], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
        commit_res = subprocess.run(
            ["git", "commit", "-m", f"AI Prism Sync: Update {os.path.basename(local_target_file)}"], 
            check=False, cwd=os.path.dirname(os.path.abspath(__file__)), capture_output=True, text=True
        )
        if "nothing to commit" in commit_res.stdout or "no changes added" in commit_res.stdout:
            print("[INFO] No changes were detected for Git commit (files are identical).")
        else:
            subprocess.run(["git", "push"], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
            print("[SUCCESS] Pushed to GitHub!")
    except subprocess.CalledProcessError as e:
        print(f"Git operation failed: {e}", file=sys.stderr)
        sys.exit(1)

def cmd_push_local_and_sync(ws_url, local_file):
    """Pushes a local file to Prism and commits to Git"""
    if not os.path.exists(local_file):
        print(f"Source file not found: {local_file}", file=sys.stderr)
        sys.exit(1)
        
    with open(local_file, 'r', encoding='utf-8') as f:
        content = f.read()
        
    content_js = json.dumps(content)
    
    # 1. Write to Prism Active Tab
    js = f"""
    (function() {{
        if (typeof monaco === 'undefined') return {{error: "Monaco not found"}};
        var editors = monaco.editor.getEditors();
        var activeEditor = null;
        for (var i = 0; i < editors.length; i++) {{
            if (editors[i].hasTextFocus() || editors.length === 1 || i === 0) {{
                activeEditor = editors[i];
                break;
            }}
        }}
        
        if (activeEditor) {{
            var model = activeEditor.getModel();
            var range = model.getFullModelRange();
            activeEditor.executeEdits("AI_Agent", [{{
                range: range,
                text: {content_js},
                forceMoveMarkers: true
            }}]);
            return {{success: true}};
        }}
        return {{error: "No active editor found to write to."}};
    }})()
    """
    result = evaluate_js(ws_url, js)
    if isinstance(result, dict) and 'error' in result:
        print(f"Prism update failed: {result['error']}", file=sys.stderr)
        sys.exit(1)
    elif isinstance(result, dict) and result.get('success'):
        print(f"[SUCCESS] Wrote {len(content)} characters from local {local_file} to the active Prism editor!")
    else:
        print(f"Unexpected result from Prism: {result}")
        sys.exit(1)

    # 2. Git Commit and Push
    print("[WAIT] Synchronizing with GitHub...")
    try:
        subprocess.run(["git", "add", local_file], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
        commit_res = subprocess.run(
            ["git", "commit", "-m", f"AI Prism Sync: Push Local Edit of {os.path.basename(local_file)}"], 
            check=False, cwd=os.path.dirname(os.path.abspath(__file__)), capture_output=True, text=True
        )
        if "nothing to commit" in commit_res.stdout or "no changes added" in commit_res.stdout:
            print("[INFO] No changes were detected for Git commit (files are identical).")
        else:
            subprocess.run(["git", "push"], check=True, cwd=os.path.dirname(os.path.abspath(__file__)))
            print("[SUCCESS] Pushed to GitHub!")
    except subprocess.CalledProcessError as e:
        print(f"Git operation failed: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Prism AI CLI Bridge")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    parser_list = subparsers.add_parser("list", help="List all files in Prism")
    
    parser_active = subparsers.add_parser("active", help="Read the currently active file in Prism")
    
    parser_read = subparsers.add_parser("read", help="Read a file from Prism by URI")
    parser_read.add_argument("filename", help="URI of the file to read")
    
    parser_write = subparsers.add_parser("write_active", help="Write to the currently active file in Prism")
    parser_write.add_argument("source", help="Local file containing the code to inject")
    
    parser_sync = subparsers.add_parser("apply_and_sync", help="Write to Prism, Save Locally, and Git Push")
    parser_sync.add_argument("target", help="The relative path to the local file to overwrite (e.g. Thesis/sisi/Templates/MAIN.tex)")
    parser_sync.add_argument("source", help="Local file containing the code to inject")
    
    parser_push_local = subparsers.add_parser("push_local", help="Push local file edits to Prism and Git Sync")
    parser_push_local.add_argument("local_file", help="The relative path to the local file to push to Prism and Git (e.g. Thesis/sisi/Templates/CH2.tex)")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
        
    ws_url = get_prism_ws_url()
    if not ws_url:
        print("Could not find Prism tab in Chrome. Make sure Chrome is running with --remote-debugging-port=9222 and Prism is open.", file=sys.stderr)
        sys.exit(1)
        
    if args.command == "list":
        cmd_list(ws_url)
    elif args.command == "active":
        cmd_active(ws_url)
    elif args.command == "read":
        cmd_read(ws_url, args.filename)
    elif args.command == "write_active":
        cmd_write_active(ws_url, args.source)
    elif args.command == "apply_and_sync":
        cmd_apply_and_sync(ws_url, args.target, args.source)
    elif args.command == "push_local":
        cmd_push_local_and_sync(ws_url, args.local_file)

if __name__ == '__main__':
    main()
