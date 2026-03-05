import http.server
import socketserver

PORT = 8000

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Inject the strict Security Headers unconditionally for ALL files
        # (This is mandatory for Godot 4 WebAssembly Multi-Threading)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Ensure caching is disabled for debugging
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

# Allow the port to be immediately reused if the script is restarted
socketserver.TCPServer.allow_reuse_address = True

with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"Serving Godot Web App securely at HTTP port {PORT}...")
    httpd.serve_forever()
