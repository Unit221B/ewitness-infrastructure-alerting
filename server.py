#!/usr/bin/env python3
"""
Cloud Run web service for Elasticsearch monitoring
Handles HTTP requests and executes bash health check script
"""
import os
import subprocess
import sys
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, HTTPServer

class MonitoringHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests with different monitoring modes"""
        try:
            # Parse query parameters
            parsed_url = urlparse(self.path)
            query_params = parse_qs(parsed_url.query)
            mode = query_params.get('mode', ['all'])[0]
            
            # Map modes to script arguments
            script_args = {
                'all': 'all',
                'daily-summary': '--daily-summary',
                'cluster': 'cluster',
                'heap': 'heap', 
                'shards': 'shards',
                'search': 'search',
                'monthly-restart': 'monthly-restart'
            }
            
            script_arg = script_args.get(mode, 'all')
            
            print(f"Executing health check with mode: {mode}")
            
            # Execute health check script
            result = subprocess.run(
                ['./elasticsearch-health-check.sh', script_arg],
                capture_output=True,
                text=True,
                timeout=240  # 4 minutes timeout
            )
            
            # Prepare response
            response_body = f"""Elasticsearch Monitoring - Mode: {mode}

Exit Code: {result.returncode}

STDOUT:
{result.stdout}

STDERR:
{result.stderr}
"""
            
            # Send HTTP response
            self.send_response(200 if result.returncode == 0 else 500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(response_body.encode())
            
        except subprocess.TimeoutExpired:
            self.send_response(504)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Health check timed out after 4 minutes')
            
        except Exception as e:
            print(f"Error executing health check: {e}")
            self.send_response(500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(f'Error: {str(e)}'.encode())
    
    def log_message(self, format, *args):
        """Override to use print instead of stderr"""
        print(f"{self.address_string()} - {format % args}")

def main():
    """Start the monitoring web server"""
    port = int(os.environ.get('PORT', 8080))
    
    print(f"Starting Elasticsearch monitoring server on port {port}")
    
    # Ensure SSH key permissions are correct
    if os.path.exists('/root/.ssh/id_rsa'):
        os.chmod('/root/.ssh/id_rsa', 0o600)
    
    server = HTTPServer(('', port), MonitoringHandler)
    print(f"Server ready at http://0.0.0.0:{port}")
    server.serve_forever()

if __name__ == '__main__':
    main()