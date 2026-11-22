import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publisher_feed import parse_feed
from check_streams import check
from refresh_catalogs import HONGGUO, Publication, episode_sources, hongguo_title


class PublisherFeedTests(unittest.TestCase):
    def setUp(self):
        self.url = 'https://media.example.org/second.mp4'
        self.digest = 'a' * 64
        self.record = {'seriesId': '11', 'episodeId': '22', 'episodeNumber': 2, 'durationMs': 171000,
                       'files': [{'url': self.url, 'sha256': self.digest}]}
        self.series = {'name': 'Test series', 'numberOfEpisodes': 2, 'episode': [], 'published_ids': ['21', '22']}

    def feed(self, *records):
        return parse_feed(json.dumps({'version': 1, 'episodes': records}))

    def test_accepts_public_query_urls_and_rejects_duplicate_episodes_or_credentials(self):
        with self.assertRaises(ValueError):
            self.feed(self.record, self.record)
        versioned = self.url + '?edition=2'
        delivery = self.feed(dict(self.record, files=[{'url': versioned, 'sha256': self.digest}]))
        self.assertIn(versioned, delivery['11']['22'].hashes)
        for url in ['http://media.example.org/2.mp4', 'https://user@media.example.org/2.mp4']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                self.feed(dict(self.record, files=[{'url': url, 'sha256': self.digest}]))

    def test_listing_and_publisher_must_agree(self):
        delivery = self.feed(self.record)['11']['22']
        with self.assertRaises(ValueError):
            episode_sources(('22', 2, {'duration': 'PT10S'}), '22', 2, delivery)
        with self.assertRaises(ValueError):
            episode_sources(None, '22', 1, delivery)

    def import_episode(self, duration=171000, digest=None):
        with (patch('refresh_catalogs.published_series', return_value=self.series),
              patch('refresh_catalogs.media_snapshot'), patch('refresh_catalogs.decode_end') as decode,
              patch('refresh_catalogs.fingerprint', return_value={'sha256': digest or self.digest, 'bytes': 1000}),
              patch('refresh_catalogs.video_track', return_value=(duration, 1280, 720, 'avc1'))):
            show = hongguo_title({'url': HONGGUO + '/detail?series_id=11'}, self.feed(self.record))
            decode.assert_called_once()
            return show

    def test_delivery_for_unlinked_episode_uses_published_order(self):
        show = self.import_episode()
        self.assertEqual(show['published_ids'], ['21', '22'])
        episode, = show['episodes']
        self.assertEqual((episode['id'], episode['title'], episode['url']), ('22', '第2集', self.url))
        self.assertEqual(episode['durationMs'], episode['listedMs'])
        self.series['published_ids'].reverse()
        with self.assertRaises(ValueError):
            self.import_episode()

    def test_preview_or_wrong_bytes_cannot_replace_full_episode(self):
        with self.assertRaises(ValueError):
            self.import_episode(duration=10000)
        with self.assertRaises(ValueError):
            self.import_episode(digest='b' * 64)

    def test_episode_page_duration_is_checked_even_without_a_media_link(self):
        episode, = self.import_episode()['episodes']
        page = episode['page']
        graph = [
            {'@type': 'TVEpisode', '@id': page + '#episode', 'url': page, 'episodeNumber': 2,
             'partOfSeason': {'@id': HONGGUO + '/detail?series_id=11#season'}, 'video': {'@id': page + '#video'}},
            {'@type': 'VideoObject', '@id': page + '#video', 'url': page, 'duration': 'PT3M',
             'about': {'@id': page + '#episode'}},
        ]
        doc = Publication(f'<script type="application/ld+json">{json.dumps(graph)}</script>')
        self.series['episode'] = [graph[0]]
        feed = self.feed(self.record)
        with (patch('refresh_catalogs.published_series', return_value=self.series),
              patch('refresh_catalogs.publication', return_value=doc),
              self.assertRaisesRegex(ValueError, 'disagrees with the episode listing')):
            hongguo_title({'url': HONGGUO + '/detail?series_id=11'}, feed)
        with (patch('check_streams.publication', return_value=doc),
              self.assertRaisesRegex(ValueError, 'disagrees with the episode listing')):
            check(('11', episode), feed, {'11': {page}})

    def test_release_check_independently_checks_the_delivery(self):
        episode, = self.import_episode()['episodes']
        feed = self.feed(self.record)
        evidence = {'bytes': episode['bytes'], 'sha256': self.digest}
        with (patch('check_streams.media_snapshot'), patch('check_streams.check_file', return_value=(171000,1280,720,'avc1')),
              patch('check_streams.fingerprint', return_value=evidence), patch('check_streams.publication') as lookup):
            result = check(('11', episode), feed, {'11': set()})
            self.assertTrue(result['full'])
            self.assertFalse(result['full_hd'])
            lookup.assert_not_called()
            changed = self.feed(dict(self.record, files=[{'url': self.url, 'sha256': 'b'*64}]))
            with self.assertRaises(ValueError):
                check(('11', episode), changed, {'11': set()})
