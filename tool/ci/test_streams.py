import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from refresh_catalogs import HONGGUO, Publication, published_video
from check_streams import complete_series


class PublicEpisodeTests(unittest.TestCase):
    def test_full_hd_first_episode_does_not_hide_missing_or_duplicate_episodes(self):
        first = {'episode_number': 1, 'full_hd': True}
        second = {'episode_number': 2, 'full_hd': True}
        self.assertTrue(complete_series([second, first], 2))
        self.assertFalse(complete_series([first], 2))
        self.assertFalse(complete_series([first, first], 2))
        self.assertFalse(complete_series([first, second, first], 2))
        self.assertFalse(complete_series([first, dict(second, full_hd=False)], 2))

    def resolve(self, media, item='22', video_id='#video', page_id='22', series='11'):
        page = f'{HONGGUO}/player/11/{page_id}'
        nodes = [{'@type': 'TVEpisode', '@id': page + '#episode', 'url': page, 'episodeNumber': 2,
                  'video': {'@id': page + video_id}, 'partOfSeries': {'@id': HONGGUO + '/detail?series_id=11#series'}},
                 {'@type': 'VideoObject', '@id': page + '#video', 'url': page,
                  'about': {'@id': page + '#episode'}, 'contentUrl': media}]
        state = {'loaderData': {'player': {'publicVideoSeo': {'itemId': item, 'seriesId': series, 'available': True}}}}
        doc = Publication(f'<script type="application/ld+json">{json.dumps({"@graph": nodes})}</script>'
                          f'<script>_ROUTER_DATA = {json.dumps(state)};</script>')
        return published_video(doc, '11', page)

    def test_public_mp4_can_move_when_episode_links_agree(self):
        self.assertEqual(self.resolve(HONGGUO + '/publications/part-two.mp4')[:2], ('22', 2))

    def test_conflicting_episode_evidence_is_rejected(self):
        url = HONGGUO + '/video/public/22/360p.mp4'
        for change in [{'item': '23'}, {'video_id': '#other'}, {'page_id': '21'}, {'series': '12'}]:
            with self.subTest(change=change):
                self.assertIsNone(self.resolve(url, **change))
        self.assertIsNone(self.resolve(url.replace('/22/', '/24/')))
        self.assertIsNone(self.resolve('https://different.example/episode.mp4'))
