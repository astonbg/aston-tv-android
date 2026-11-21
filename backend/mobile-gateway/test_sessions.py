import importlib.util
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError


class SessionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {
            'ASTON_PUBLIC_SIGNING_KEY': 'test-only-' * 8,
            'ASTON_PUBLIC_SESSION_FILE': str(Path(self.temp.name) / 'sessions.json'),
        })
        self.env.start()
        self.gateway = self.load()
        self.sid = 's' * 48
        self.token = 'test-device-token-' * 4
        self.gateway.sessions[self.sid] = {'token': self.token, 'exp': time.time()+1000, 'checked': 0}
        self.gateway.save_sessions_locked()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def load(self):
        spec = importlib.util.spec_from_file_location('session_test_gateway', Path(__file__).with_name('gateway.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def handler(self, module):
        handler = module.Handler.__new__(module.Handler)
        handler.headers = {'Cookie': 'aston_public_sid='+self.sid, 'Host': '127.0.0.1'}
        return handler

    def test_restart_restores_session_and_rechecks_core(self):
        restarted = self.load()
        with patch.object(restarted, 'core_json', return_value={'name': 'Phone'}) as core:
            self.assertEqual(self.handler(restarted).auth(), (self.token, 'Phone'))
            core.assert_called_once()
        self.assertGreater(restarted.sessions[self.sid]['exp'], time.time()+365*86400)

    def test_transient_failure_keeps_pairing_and_returns_unavailable(self):
        handler = self.handler(self.gateway)
        for error in (URLError('offline'), HTTPError('http://core', 503, 'offline', {}, None)):
            with patch.object(self.gateway, 'core_json', side_effect=error), patch.object(handler, 'fail') as fail:
                self.assertIsNone(handler.must_auth())
                self.assertEqual(fail.call_args.args[0], 503)
            self.assertIn(self.sid, self.gateway.load_sessions())

    def test_revoked_device_removed_from_memory_and_disk(self):
        handler = self.handler(self.gateway)
        with patch.object(self.gateway, 'core_json', side_effect=HTTPError('http://core', 401, 'revoked', {}, None)), patch.object(handler, 'fail') as fail:
            self.assertIsNone(handler.must_auth())
            self.assertEqual(fail.call_args.args[0], 401)
        self.assertNotIn(self.sid, self.gateway.sessions)
        self.assertNotIn(self.sid, self.gateway.load_sessions())

    def test_cookie_is_renewed_with_http_only(self):
        handler = self.handler(self.gateway)
        handler.authenticated_sid = self.sid
        with patch.object(handler, 'send_response'), patch.object(handler, 'send_header') as header, patch.object(handler, 'end_headers'):
            handler.headers_common(200)
            cookies = [call.args[1] for call in header.call_args_list if call.args[0]=='Set-Cookie']
        self.assertEqual(len(cookies), 1)
        self.assertIn('HttpOnly', cookies[0])
        self.assertIn('Max-Age='+str(self.gateway.SESSION_LIFETIME), cookies[0])


if __name__ == '__main__':
    unittest.main()
