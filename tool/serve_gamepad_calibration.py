"""只在本机提供手柄校准单页，不列出Downloads，不接收上传或修改游戏文件。"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8768)
    parser.add_argument('--file', type=Path, default=Path(__file__).with_name('gamepad_calibration.html'))
    args = parser.parse_args()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.split('?', 1)[0] not in ('/', '/gamepad-calibration.html'):
                self.send_error(404)
                return
            body = args.file.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Permissions-Policy', 'gamepad=(self)')
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'手柄校准网页：http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
