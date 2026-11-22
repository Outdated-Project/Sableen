"""Convert a clear ByteVC2 MP4 to AVC and measure the output against its source."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

from refresh_catalogs import COMPATIBILITY_CODECS, fingerprint, media_snapshot


def probe(executable, path):
    args = [executable, '-v', 'error', '-protocol_whitelist', 'file', '-f', 'mov',
            '-count_frames', '-show_streams', '-of', 'json', str(path)]
    streams = json.loads(subprocess.check_output(args))['streams']
    video = next(s for s in streams if s['codec_type'] == 'video')
    audio = [s for s in streams if s['codec_type'] == 'audio']
    return video, audio


def convert(ffmpeg, src, out, preset, audio):
    command = [ffmpeg, '-nostdin', '-hide_banner', '-v', 'error', '-xerror', '-y',
               '-protocol_whitelist', 'file', '-f', 'mov', '-i', str(src), '-map', '0:v:0',
               '-map', '0:a?', '-c:v', 'libx264', '-preset', preset, '-crf', '18',
               '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough', '-c:a', 'copy']
    for index, stream in enumerate(audio):
        if stream['codec_name'] != 'aac':
            command.extend([f'-c:a:{index}', 'aac', f'-b:a:{index}', '192k'])
    start = time.perf_counter()
    subprocess.run(command + ['-movflags', '+faststart', str(out)], check=True)
    return time.perf_counter() - start


def verify(ffmpeg, ffprobe, src, out, original):
    source_video, source_audio = original
    video, audio = probe(ffprobe, out)
    frames = int(source_video['nb_read_frames'])
    if (video['codec_name'] != 'h264' or frames <= 0 or len(audio) != len(source_audio)
            or any(video[k] != source_video[k] for k in ('width', 'height', 'nb_read_frames'))):
        raise ValueError('Output track, dimensions or decoded frame count changed')
    def interval(s):
        start, duration = float(s['start_time']), float(s['duration'])
        if not math.isfinite(start + duration) or duration <= 0:
            raise ValueError('Invalid track timestamps')
        return start, start + duration
    # Compare every track relative to video start, including intentional audio offsets.
    offsets = []
    for a, b in zip([source_video, *source_audio], [video, *audio], strict=True):
        offsets.extend(abs((x - interval(source_video)[0]) - (y - interval(video)[0]))
                       for x, y in zip(interval(a), interval(b)))
    if max(offsets) > 0.1:
        raise ValueError('Track boundaries changed by more than 100 ms')
    quality = subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-xerror', '-nostats',
                              '-protocol_whitelist', 'file', '-i', str(src), '-protocol_whitelist',
                              'file', '-i', str(out), '-filter_complex',
                              '[0:v:0]setpts=PTS-STARTPTS[ref];[1:v:0]setpts=PTS-STARTPTS[enc];[ref][enc]ssim[v]',
                              '-map', '[v]', '-map', '1:a?', '-f', 'null', '-'],
                             capture_output=True, text=True, check=True)
    score = re.search(r'\bAll:([0-9.]+)', quality.stderr)
    if not score:
        raise ValueError('No full-reference SSIM result')
    return {'codec': video['codec_name'], 'width': video['width'], 'height': video['height'],
            'seconds': float(video['duration']), 'frames': frames, 'audio_tracks': len(audio),
            'max_track_boundary_delta_ms': round(max(offsets) * 1000, 2), 'ssim': float(score[1]),
            **fingerprint(out)}


def prepare_rendition(url, evidence, folder, tag='bvc2'):
    folder.mkdir(exist_ok=True)
    ffmpeg = os.environ.get('SABLEEN_FFMPEG', 'ffmpeg')
    ffprobe = os.environ.get('SABLEEN_FFPROBE', 'ffprobe')
    with media_snapshot(url) as src, tempfile.TemporaryDirectory(dir=folder) as work:
        if fingerprint(src) != evidence:
            raise ValueError('Video source changed before conversion')
        original = probe(ffprobe, src)
        check_source(original[0], tag)
        out = Path(work) / 'episode.mp4'
        convert(ffmpeg, src, out, 'veryfast', original[1])
        result = verify(ffmpeg, ffprobe, src, out, original)
        out.replace(folder / f"{result['sha256']}.mp4")
        return {k: result[k] for k in ('bytes', 'sha256')}


def check_source(video, tag='bvc2'):
    if tag not in COMPATIBILITY_CODECS or video.get('codec_tag_string') != tag or video.get('codec_name') != COMPATIBILITY_CODECS[tag]:
        raise ValueError(f'Expected a {tag} input and an ffprobe build with its decoder')
    if video.get('color_transfer') in ('smpte2084', 'arib-std-b67'):
        raise ValueError('HDR input requires a colour-managed HDR conversion')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--ffprobe', default='ffprobe')
    parser.add_argument('--benchmark', action='store_true', help='Alternate medium and veryfast over three pairs')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new output path')
    original = probe(args.ffprobe, args.input.resolve())
    video, audio = original
    check_source(video)
    report = {'input': fingerprint(args.input), 'ffmpeg': subprocess.check_output(
        [args.ffmpeg, '-version'], text=True).splitlines()[0], 'presets': {}}
    with tempfile.TemporaryDirectory(dir=args.output.parent) as work:
        runs = [['veryfast']] if not args.benchmark else [
            ['medium', 'veryfast'], ['veryfast', 'medium'], ['medium', 'veryfast']]
        for pair in runs:
            for preset in pair:
                out = Path(work) / f'{preset}.mp4'
                seconds = convert(args.ffmpeg, args.input.resolve(), out, preset, audio)
                row = report['presets'].setdefault(preset, {'wall_seconds': []})
                row['wall_seconds'].append(round(seconds, 6))
        for preset, row in report['presets'].items():
            row['median_seconds'] = statistics.median(row['wall_seconds'])
            row['output'] = verify(args.ffmpeg, args.ffprobe, args.input.resolve(), Path(work) / f'{preset}.mp4', original)
        if args.benchmark:
            report['speedup'] = report['presets']['medium']['median_seconds'] / report['presets']['veryfast']['median_seconds']
        # An exclusive hard link publishes only a complete file, including if two jobs race.
        args.output.hardlink_to(Path(work) / 'veryfast.mp4')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
