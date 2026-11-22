import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from refresh_catalogs import HONGGUO, Publication, playable_encodings, public_encodings, published_series, published_video, quality_files
from check_streams import complete_series


class PublicEpisodeTests(unittest.TestCase):
    def test_resolution_switch_keeps_distinct_sizes_with_the_same_cut(self):
        def media(label, duration, width, height):
            return label, duration, width, height, {'sha256': label, 'bytes': 100}, 'avc1'
        hd = media('hd', 180000, 1080, 1920)
        sd = media('sd', 179900, 360, 640)
        preview = media('preview', 10000, 240, 426)
        mirror = media('mirror', 179900, 360, 640)
        hevc = (*media('hevc', 180100, 720, 1280)[:-1], 'hvc1')
        choices = quality_files(hd, [preview, sd, hevc, hd, mirror], 180000)
        self.assertEqual([f['url'] for f in choices], ['hd', 'sd', 'hevc'])
        self.assertEqual(quality_files(hd, [preview, hd], 180000), [])

    def test_unconvertible_hdr_keeps_the_other_verified_files(self):
        def file(label, w, h, codec):
            return label, 10000, w, h, {'bytes': 123, 'sha256': label}, codec
        hdr = file('hdr', 2160, 3840, 'hvc1')
        sd = file('sd', 360, 640, 'avc1')
        hd = file('hd', 1080, 1920, 'avc1')
        with patch('transcode_bytevc2.prepare_rendition', side_effect=ValueError('HDR')) as convert:
            primary, choices, assets = playable_encodings([sd, hdr, hd], 10000, Path('.'))
        convert.assert_called_once()
        self.assertEqual(primary, hd)
        self.assertEqual([f['url'] for f in choices], ['hd', 'sd'])
        self.assertEqual(assets, {})

    def test_full_hd_first_episode_does_not_hide_missing_or_duplicate_episodes(self):
        first = {'episode_number': 1, 'full_hd': True, 'missing_published_sizes': []}
        second = {'episode_number': 2, 'full_hd': True, 'missing_published_sizes': []}
        self.assertTrue(complete_series([second, first], 2))
        self.assertFalse(complete_series([first], 2))
        self.assertFalse(complete_series([first, first], 2))
        self.assertFalse(complete_series([first, second, first], 2))
        self.assertFalse(complete_series([first, dict(second, full_hd=False)], 2))
        self.assertFalse(complete_series([first, dict(second, missing_published_sizes=[(720, 1280)])], 2))

    def resolve(self, media, item='22', video_id='#video', page_id='22', series='11', encodings=None, extra=(), available=True):
        page = f'{HONGGUO}/player/11/{page_id}'
        nodes = [{'@type': 'TVEpisode', '@id': page + '#episode', 'url': page, 'episodeNumber': 2,
                  'video': {'@id': page + video_id}, 'partOfSeries': {'@id': HONGGUO + '/detail?series_id=11#series'}},
                 {'@type': 'VideoObject', '@id': page + '#video', 'url': page,
                   'about': {'@id': page + '#episode'}, 'contentUrl': media, 'encoding': encodings}, *extra]
        state = {'loaderData': {'player': {'publicVideoSeo': {'itemId': item, 'seriesId': series, 'available': available}}}}
        doc = Publication(f'<script type="application/ld+json">{json.dumps({"@graph": nodes})}</script>'
                          f'<script>_ROUTER_DATA = {json.dumps(state)};</script>')
        return published_video(doc, '11', page)

    def test_public_mp4_can_move_when_episode_links_agree(self):
        self.assertEqual(self.resolve(HONGGUO + '/publications/part-two.mp4')[:2], ('22', 2))
        self.assertEqual(self.resolve('https://media.hongguoduanju.com/published/part-two.mp4')[:2], ('22', 2))
        self.assertIsNone(self.resolve('https://hongguoduanju.com.example.org/part-two.mp4'))

    def test_public_encodings_without_a_default_url(self):
        base = HONGGUO + '/video/public/22/'
        reference = {'@id': '#hd'}
        graph = [{'@id': '#hd', '@type': 'MediaObject', 'contentUrl': base + '1080p.mp4'}]
        encodings = [reference, {'contentUrl': base + '360p.mp4'}, {'contentUrl': base.replace('/22/', '/23/') + '720p.mp4'}]
        item, _, video = self.resolve(None, encodings=encodings, extra=graph)
        self.assertEqual(public_encodings(video, item), [base + '1080p.mp4', base + '360p.mp4'])
        self.assertIsNone(self.resolve(None, encodings=encodings, extra=graph, available=False))
        self.assertIsNone(self.resolve(None, encodings=[reference], extra=graph * 2))

    def test_detail_links_add_only_episodes_identified_in_the_same_season(self):
        detail = HONGGUO + '/detail?series_id=11'
        node = {'@type': 'TVSeries', 'url': detail, 'numberOfEpisodes': 3}
        metadata = {'loaderData': {'detail_page': {'seriesDetail': {'series_id': '11', 'vid_list': ['21', '22', '23']}}}}
        doc = Publication(f'<script type="application/ld+json">{json.dumps([node])}</script>'
                          f'<script>_ROUTER_DATA = {json.dumps(metadata)};</script>'
                          '<a href="/player/11"></a><a href="/player/11/23"></a><a href="/player/12/22"></a>'
                          '<a href="/player/11/24"></a>')
        with patch('refresh_catalogs.publication', return_value=doc):
            self.assertEqual([e['episodeNumber'] for e in published_series(detail)['episode']], [1, 3])

    def test_conflicting_episode_evidence_is_rejected(self):
        url = HONGGUO + '/video/public/22/360p.mp4'
        for change in [{'item': '23'}, {'video_id': '#other'}, {'page_id': '21'}, {'series': '12'}]:
            with self.subTest(change=change):
                self.assertIsNone(self.resolve(url, **change))
        self.assertIsNone(self.resolve(url.replace('/22/', '/24/')))
        self.assertIsNone(self.resolve('https://different.example/episode.mp4'))
