"""CORS behavior and client disconnects through the ASGI middleware stack."""

import asyncio
from unittest.mock import AsyncMock, Mock, patch

from asgiref.testing import ApplicationCommunicator
from django.core.handlers.asgi import ASGIHandler
from django.http import HttpResponse
from django.test import RequestFactory, SimpleTestCase, override_settings

from defensys_backend.cors import LocalCorsMiddleware


@override_settings(DEBUG=True, CORS_ALLOW_LAN=True)
class LocalCorsMiddlewareTests(SimpleTestCase):
    def test_sync_response_keeps_cors_and_pdf_headers(self):
        request = RequestFactory().get(
            '/media/report.pdf', HTTP_ORIGIN='http://192.168.1.3:57583',
        )
        response = LocalCorsMiddleware(lambda request: HttpResponse('pdf'))(request)
        self.assertEqual(response['Access-Control-Allow-Origin'], request.headers['Origin'])
        self.assertEqual(response['Accept-Ranges'], 'bytes')
        self.assertEqual(response['Cache-Control'], 'public, max-age=3600')

    def test_sync_preflight_does_not_call_view(self):
        view = Mock()
        request = RequestFactory().options('/', HTTP_ORIGIN='http://localhost:57583')
        response = LocalCorsMiddleware(view)(request)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response['Access-Control-Allow-Origin'], request.headers['Origin'])
        view.assert_not_called()

    async def test_async_response_keeps_cors_and_pdf_headers(self):
        view = AsyncMock(return_value=HttpResponse('pdf'))
        request = RequestFactory().get(
            '/media/report.pdf', HTTP_ORIGIN='http://192.168.1.3:57583',
        )
        response = await LocalCorsMiddleware(view)(request)
        self.assertEqual(response['Access-Control-Allow-Origin'], request.headers['Origin'])
        self.assertEqual(response['Accept-Ranges'], 'bytes')
        self.assertEqual(response['Cache-Control'], 'public, max-age=3600')
        view.assert_awaited_once_with(request)

    async def test_async_preflight_does_not_call_view(self):
        view = AsyncMock()
        request = RequestFactory().options('/', HTTP_ORIGIN='http://localhost:57583')
        response = await LocalCorsMiddleware(view)(request)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response['Access-Control-Allow-Origin'], request.headers['Origin'])
        view.assert_not_called()

    @override_settings(DEBUG=False, CORS_ALLOWED_ORIGINS=['https://defensys.example'])
    async def test_async_preflight_respects_production_origin_allowlist(self):
        middleware = LocalCorsMiddleware(AsyncMock())
        for origin in ['https://defensys.example', 'http://192.168.1.3:57583']:
            with self.subTest(origin=origin):
                request = RequestFactory().options('/', HTTP_ORIGIN=origin)
                response = await middleware(request)
                self.assertEqual(response.status_code, 204)
                self.assertEqual(
                    response.get('Access-Control-Allow-Origin'),
                    origin if origin == 'https://defensys.example' else None,
                )

    async def test_client_disconnect_does_not_log_shielded_future_error(self):
        """Python 3.14 reports nested sync/async cancellation as a future error."""
        entered = asyncio.Event()
        cancelled = asyncio.Event()

        async def slow_response(handler, request):
            entered.set()
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                cancelled.set()
                raise

        loop = asyncio.get_running_loop()
        previous_handler = loop.get_exception_handler()
        errors = []
        loop.set_exception_handler(lambda loop, context: errors.append(context))
        try:
            # Keep the real configured middleware; replace only the slow view.
            with patch.object(ASGIHandler, '_get_response_async', slow_response):
                app = ApplicationCommunicator(ASGIHandler(), {
                    'type': 'http', 'http_version': '1.1', 'method': 'GET',
                    'path': '/api/health/', 'query_string': b'', 'scheme': 'http',
                    'headers': [(b'host', b'localhost')],
                })
                try:
                    await app.send_input({'type': 'http.request', 'body': b''})
                    await asyncio.wait_for(entered.wait(), timeout=2)
                    await app.send_input({'type': 'http.disconnect'})
                    await app.wait(timeout=2)
                    await asyncio.sleep(0)
                    self.assertTrue(cancelled.is_set())
                    self.assertEqual(errors, [])
                finally:
                    app.stop()
        finally:
            loop.set_exception_handler(previous_handler)
