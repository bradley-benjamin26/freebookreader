from subprocess import check_call
import json
import os
import shutil
from time import strftime
import sys
import urllib.request

from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError

from books import utils
from books.models import *


TEMP_PATH = settings.CATALOG_TEMP_DIR

URL = 'https://gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2'
DOWNLOAD_PATH = os.path.join(TEMP_PATH, 'catalog.tar.bz2')

MOVE_SOURCE_PATH = os.path.join(TEMP_PATH, 'cache/epub')
MOVE_TARGET_PATH = settings.CATALOG_RDF_DIR

LOG_DIRECTORY = settings.CATALOG_LOG_DIR
LOG_FILE_NAME = strftime('%Y-%m-%d_%H%M%S') + '.txt'
LOG_PATH = os.path.join(LOG_DIRECTORY, LOG_FILE_NAME)


# This gives a set of the names of the subdirectories in the given file path.
def get_directory_set(path):
    directory_set = set()
    for directory_item in os.listdir(path):
        item_path = os.path.join(path, directory_item)
        if os.path.isdir(item_path):
            directory_set.add(directory_item)
    return directory_set


# The names of the subdirectories that are book ID numbers.
def get_book_directory_set(path):
    if not os.path.isdir(path):
        return set()
    return {name for name in get_directory_set(path) if name.isdigit()}


def log(*args):
    print(*args)
    if not os.path.exists(LOG_DIRECTORY):
        os.makedirs(LOG_DIRECTORY)
    with open(LOG_PATH, 'a') as log_file:
        text = ' '.join(args) + '\n'
        log_file.write(text)


def put_catalog_in_db():
    book_ids = []
    for directory_item in os.listdir(settings.CATALOG_RDF_DIR):
        item_path = os.path.join(settings.CATALOG_RDF_DIR, directory_item)
        if os.path.isdir(item_path):
            try:
                book_id = int(directory_item)
            except ValueError:
                # Ignore the item if it's not a book ID number.
                pass
            else:
                book_ids.append(book_id)
    book_ids.sort()
    book_directories = [str(id) for id in book_ids]

    for directory in book_directories:
        id = int(directory)

        if (id > 0) and (id % 500 == 0):
            log('    %d' % id)

        book_path = os.path.join(
            settings.CATALOG_RDF_DIR,
            directory,
            'pg' + directory + '.rdf'
        )

        book = utils.get_book(id, book_path)

        try:
            '''Make/update the book.'''

            book_in_db = Book.objects.filter(gutenberg_id=id)

            if book_in_db.exists():
                book_in_db = book_in_db[0]
                book_in_db.copyright = book['copyright']
                book_in_db.download_count = book['downloads']
                book_in_db.media_type = book['type']
                book_in_db.title = book['title']
                book_in_db.release_date = book['release_date']
                book_in_db.last_updated = book['last_updated']
                book_in_db.credits = book['credits']
                book_in_db.original_publication = book['original_publication']
                book_in_db.save()
            else:
                book_in_db = Book.objects.create(
                    gutenberg_id=id,
                    copyright=book['copyright'],
                    download_count=book['downloads'],
                    media_type=book['type'],
                    title=book['title'],
                    release_date=book['release_date'],
                    last_updated=book['last_updated'],
                    credits=book['credits'],
                    original_publication=book['original_publication']
                )

            ''' Make/update the authors. '''

            authors = []
            for author in book['authors']:
                person = get_or_create_person(author)
                authors.append(person)

            book_in_db.authors.clear()
            for author in authors:
                book_in_db.authors.add(author)

            ''' Make/update the editors. '''

            editors = []
            for editor in book['editors']:
                person = get_or_create_person(editor)
                editors.append(person)

            book_in_db.editors.clear()
            for editor in editors:
                book_in_db.editors.add(editor)

            ''' Make/update the translators. '''

            translators = []
            for translator in book['translators']:
                person = get_or_create_person(translator)
                translators.append(person)

            book_in_db.translators.clear()
            for translator in translators:
                book_in_db.translators.add(translator)

            ''' Make/update the book shelves. '''

            bookshelves = []
            for shelf in book['bookshelves']:
                shelf_in_db = Bookshelf.objects.filter(name=shelf)
                if shelf_in_db.exists():
                    shelf_in_db = shelf_in_db[0]
                else:
                    shelf_in_db = Bookshelf.objects.create(name=shelf)
                bookshelves.append(shelf_in_db)

            book_in_db.bookshelves.clear()
            for bookshelf in bookshelves:
                book_in_db.bookshelves.add(bookshelf)

            ''' Make/update the formats. '''

            old_formats = Format.objects.filter(book=book_in_db)

            format_ids = []
            for format_ in book['formats']:
                format_in_db = Format.objects.filter(
                    book=book_in_db,
                    mime_type=format_,
                    url=book['formats'][format_]
                )
                if format_in_db.exists():
                    format_in_db = format_in_db[0]
                else:
                    format_in_db = Format.objects.create(
                        book=book_in_db,
                        mime_type=format_,
                        url=book['formats'][format_]
                    )
                format_ids.append(format_in_db.id)

            for old_format in old_formats:
                if old_format.id not in format_ids:
                    old_format.delete()

            ''' Make/update the languages. '''

            languages = []
            for language in book['languages']:
                language_in_db = Language.objects.filter(code=language)
                if language_in_db.exists():
                    language_in_db = language_in_db[0]
                else:
                    language_in_db = Language.objects.create(code=language)
                languages.append(language_in_db)

            book_in_db.languages.clear()
            for language in languages:
                book_in_db.languages.add(language)

            ''' Make/update subjects. '''

            subjects = []
            for subject in book['subjects']:
                subject_in_db = Subject.objects.filter(name=subject)
                if subject_in_db.exists():
                    subject_in_db = subject_in_db[0]
                else:
                    subject_in_db = Subject.objects.create(name=subject)
                subjects.append(subject_in_db)

            book_in_db.subjects.clear()
            for subject in subjects:
                book_in_db.subjects.add(subject)

            ''' Make/update summaries. '''

            old_summaries = Summary.objects.filter(book=book_in_db)

            summary_ids = []
            for summary in book['summaries']:
                summary_in_db = Summary.objects.filter(book=book_in_db, text=summary)
                if summary_in_db.exists():
                    summary_in_db = summary_in_db[0]
                else:
                    summary_in_db = Summary.objects.create(
                        book=book_in_db, text=summary
                    ) 
                summary_ids.append(summary_in_db.id)

            for old_summary in old_summaries:
                if old_summary.id not in summary_ids:
                    old_summary.delete()

        except Exception as error:
            book_json = json.dumps(book, indent=4, default=str)
            log(
                '  Error while putting this book info in the database:\n',
                book_json,
                '\n'
            )
            raise error


def get_or_create_person(data):
    person = Person.objects.filter(
        name=data['name'],
        birth_year=data['birth'],
        death_year=data['death']
    )

    if person.exists():
        person = person[0]
    else:
        person = Person.objects.create(
            name=data['name'],
            birth_year=data['birth'],
            death_year=data['death']
        )
    
    return person


def send_log_email():
    if not (settings.ADMIN_EMAILS or settings.EMAIL_HOST_ADDRESS):
        return

    log_text = ''
    with open(LOG_PATH, 'r') as log_file:
        log_text = log_file.read()

    email_html = '''
        <h1 style="color: #333;
                   font-family: 'Helvetica Neue', sans-serif;
                   font-size: 64px;
                   font-weight: 100;
                   text-align: center;">
            Gutendex
        </h1>

        <p style="color: #333;
                  font-family: 'Helvetica Neue', sans-serif;
                  font-size: 24px;
                  font-weight: 200;">
            Here is the log from your catalog retrieval:
        </p>

        <pre style="color:#333;
                    font-family: monospace;
                    font-size: 16px;
                    margin-left: 32px">''' + log_text + '</pre>'

    email_text = '''GUTENDEX

    Here is the log from your catalog retrieval:

    ''' + log_text

    send_mail(
        subject='Catalog retrieval',
        message=email_text,
        html_message=email_html,
        from_email=settings.EMAIL_HOST_ADDRESS,
        recipient_list=settings.ADMIN_EMAILS
    )


class Command(BaseCommand):
    help = 'This replaces the catalog files with the latest ones.'

    def handle(self, *args, **options):
        # Every step must succeed before anything is deleted, and a failure must reach cron or systemd as a
        # failed run (REVIEW-2026-10-11-main.md #6, #7, #9).
        owns_temp = False
        failure = None
        try:
            date_and_time = strftime('%H:%M:%S on %B %d, %Y')
            log('Starting script at', date_and_time)

            log('  Making temporary directory...')
            try:
                # Creating it is also the claim to run: a second run stops here and leaves it alone.
                os.makedirs(TEMP_PATH)
            except FileExistsError:
                raise CommandError(
                    'The temporary path, `' + TEMP_PATH + '`, already exists. '
                    'Another update may be running; if none is, delete it.'
                )
            owns_temp = True

            log('  Downloading compressed catalog...')
            urllib.request.urlretrieve(URL, DOWNLOAD_PATH)

            log('  Decompressing catalog...')
            with open(os.devnull, 'w') as null:
                with open(LOG_PATH, 'a') as log_file:
                    check_call(
                        ['tar', 'fjvx', DOWNLOAD_PATH, '-C', TEMP_PATH],
                        stdout=null,
                        stderr=log_file
                    )

            log('  Detecting stale directories...')
            if not os.path.exists(MOVE_TARGET_PATH):
                os.makedirs(MOVE_TARGET_PATH)
            new_directory_set = get_book_directory_set(MOVE_SOURCE_PATH)
            if not new_directory_set:
                raise CommandError('The downloaded catalog has no books in it.')
            old_directory_set = get_book_directory_set(MOVE_TARGET_PATH)
            stale_ids = [int(d) for d in old_directory_set - new_directory_set]

            # rsync's --delete-after removes the stale directories once the copy is done.
            log('  Replacing old catalog files...')
            with open(os.devnull, 'w') as null:
                with open(LOG_PATH, 'a') as log_file:
                    check_call(
                        [
                            'rsync',
                            '-va',
                            '--delete-after',
                            MOVE_SOURCE_PATH + '/',
                            MOVE_TARGET_PATH
                        ],
                        stdout=null,
                        stderr=log_file
                    )

            log('  Putting the catalog in the database...')
            put_catalog_in_db()

            log('  Removing books that left the catalog...')
            Book.objects.filter(gutenberg_id__in=stale_ids).delete()

            log('Done!\n')
        except Exception as error:
            failure = error
            log('Error:', str(error))
            log('')
        finally:
            if owns_temp:
                log('  Removing temporary files...')
                shutil.rmtree(TEMP_PATH, ignore_errors=True)

        send_log_email()
        if failure is not None:
            if isinstance(failure, CommandError):
                raise failure
            raise CommandError(str(failure)) from failure
