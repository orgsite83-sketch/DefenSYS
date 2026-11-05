from unittest.mock import patch

from django.test import SimpleTestCase, override_settings

from notifications.sms_service import _send_via_android_gateway


@override_settings(
    SMS_GATEWAY_USERNAME='test-user',
    SMS_GATEWAY_PASSWORD='test-password',
    SMS_GATEWAY_API_KEY='',
)
class AndroidGatewayTests(SimpleTestCase):
    @override_settings(
        SMS_GATEWAY_URL='https://api.sms-gate.app/3rdparty/v1/messages/',
    )
    @patch('notifications.sms_service.requests.post')
    def test_cloud_endpoint_and_payload(self, post):
        post.return_value.status_code = 202
        self.assertTrue(_send_via_android_gateway('+639171234567', 'Test code'))
        post.assert_called_once_with(
            'https://api.sms-gate.app/3rdparty/v1/messages',
            json={
                'textMessage': {'text': 'Test code'},
                'phoneNumbers': ['+639171234567'],
            },
            headers={'Content-Type': 'application/json'},
            auth=('test-user', 'test-password'),
            timeout=10,
        )

    @override_settings(SMS_GATEWAY_URL='http://192.168.1.150:8080')
    @patch('notifications.sms_service.requests.post')
    def test_local_endpoint_keeps_legacy_payload(self, post):
        post.return_value.status_code = 200
        self.assertTrue(_send_via_android_gateway('09171234567', 'Test code'))
        self.assertEqual(post.call_args.args[0], 'http://192.168.1.150:8080/message')
        self.assertEqual(post.call_args.kwargs['json']['message'], 'Test code')
        self.assertEqual(post.call_args.kwargs['json']['phoneNumbers'], ['+639171234567'])

    @override_settings(SMS_GATEWAY_URL='https://api.sms-gate.app/3rdparty/v1/messages')
    @patch('notifications.sms_service.requests.post')
    def test_recipient_phone_formats(self, post):
        post.return_value.status_code = 202
        for source, expected in (
            ('09171234567', '+639171234567'),
            ('0917 123-4567', '+639171234567'),
            ('639171234567', '+639171234567'),
            ('+639171234567', '+639171234567'),
            ('+12025550123', '+12025550123'),
            ('0917', '0917'),
        ):
            with self.subTest(source=source):
                self.assertTrue(_send_via_android_gateway(source, 'Test code'))
                self.assertEqual(post.call_args.kwargs['json']['phoneNumbers'], [expected])
