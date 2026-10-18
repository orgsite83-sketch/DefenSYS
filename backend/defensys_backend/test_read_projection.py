from django.contrib.auth import get_user_model
from django.db import connection, transaction
from django.test import TestCase

from .read_projection import read_memoize, read_projection


@read_memoize(copy=True)
def directory_projection(user_id):
    return {'name': get_user_model().objects.get(pk=user_id).first_name, 'items': []}


class ReadProjectionTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username='read-projection', first_name='Before')

    def test_response_reuse_does_not_persist_across_requests(self):
        with read_projection(), self.assertNumQueries(1):
            first = directory_projection(self.user.pk)
            first['items'].append('local presentation')
            self.assertEqual(directory_projection(self.user.pk)['items'], [])
        get_user_model().objects.filter(pk=self.user.pk).update(first_name='Next request')
        with read_projection(), self.assertNumQueries(1):
            self.assertEqual(directory_projection(self.user.pk)['name'], 'Next request')

    def test_write_invalidates_previously_read_values(self):
        with read_projection():
            self.assertEqual(directory_projection(self.user.pk)['name'], 'Before')
            get_user_model().objects.filter(pk=self.user.pk).update(first_name='Saved')
            self.assertEqual(directory_projection(self.user.pk)['name'], 'Saved')

    def test_rolled_back_write_cannot_leave_a_cached_value(self):
        with read_projection():
            try:
                with transaction.atomic():
                    get_user_model().objects.filter(pk=self.user.pk).update(first_name='Rolled back')
                    self.assertEqual(directory_projection(self.user.pk)['name'], 'Rolled back')
                    raise ValueError('rollback')
            except ValueError:
                pass
            self.assertEqual(directory_projection(self.user.pk)['name'], 'Before')

    def test_exception_resets_projection_scope(self):
        try:
            with read_projection():
                directory_projection(self.user.pk)
                raise ValueError('failed read')
        except ValueError:
            pass
        get_user_model().objects.filter(pk=self.user.pk).update(first_name='Recovered')
        self.assertEqual(directory_projection(self.user.pk)['name'], 'Recovered')
