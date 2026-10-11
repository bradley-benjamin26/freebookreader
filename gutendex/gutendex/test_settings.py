"""Settings for `python manage.py test --settings=gutendex.test_settings`.

Uses in-memory SQLite so the tests need no Postgres privileges and can never
touch the real catalog database.
"""
from .settings import *  # noqa: F401,F403

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}
