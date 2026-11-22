use courierust::courierust_http::uri::Url;
use nextjson::NsonDeserialize;
use std::collections::{HashMap, HashSet};
use tzcraft::Duration;

const MAX_HISTORY_BYTES: usize = 1 << 20;
const MAX_CATALOG_BYTES: usize = 8 << 20;
const HISTORY_LIMIT: usize = 512;
const WATCH_PRIOR_MS: f64 = 60_000.0;

#[derive(Clone, Debug, NsonDeserialize)]
pub struct AdBreak {
    pub start_ms: u32,
    pub end_ms: u32,
}

#[derive(Clone, Debug, NsonDeserialize)]
pub struct VideoEncoding {
    pub width: u32,
    pub height: u32,
    pub url: String,
    pub bytes: u32,
    pub sha256: String,
}

#[derive(Clone, Debug, NsonDeserialize)]
pub struct Episode {
    pub id: String,
    pub title: String,
    pub url: String,
    pub page: Option<String>,
    pub bytes: Option<u32>,
    pub sha256: Option<String>,
    pub mirrors: Option<Vec<String>>,
    pub encodings: Option<Vec<VideoEncoding>>,
    #[serde(rename = "durationMs")]
    pub duration_ms: Option<u32>,
    #[serde(rename = "listedMs")]
    pub listed_ms: Option<u32>,
    pub ad_breaks: Option<Vec<AdBreak>>,
}

#[derive(Clone, Debug, NsonDeserialize)]
pub struct Drama {
    pub id: String,
    pub title: String,
    pub tags: Vec<String>,
    pub cover: Option<String>,
    pub episode_count: Option<u32>,
    pub published_ids: Option<Vec<String>>,
    pub episodes: Vec<Episode>,
}

#[derive(NsonDeserialize)]
struct Catalog {
    version: u32,
    dramas: Vec<Drama>,
}

#[derive(Clone, Debug, PartialEq, rustbinary::CompactBinary)]
pub struct Progress {
    pub drama: String,
    pub episode: String,
    pub position_ms: u32,
    pub duration_ms: u32,
    pub watched_ms: u32,
    pub updated: u32,
    pub completed: bool,
}

pub struct Candidate {
    pub id: String,
    pub tags: Vec<String>,
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

fn valid_text(s: &str, max: usize) -> bool {
    !s.trim().is_empty() && s.len() <= max && !s.chars().any(char::is_control)
}

pub fn valid_address(address: &str) -> bool {
    if address.len() > 4096
        || !address.starts_with("https://")
        || !address.is_ascii()
        || address
            .bytes()
            .any(|b| b <= 32 || matches!(b, 127 | b'\\' | b'#'))
    {
        return false;
    }
    let Ok(url) = Url::parse(address) else {
        return false;
    };
    url.userinfo.is_none()
        && (url.host.parse::<std::net::IpAddr>().is_ok()
            || (url.host.split('.').all(|label| {
                !label.is_empty()
                    && !label.starts_with('-')
                    && !label.ends_with('-')
                    && label
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'-')
            }) && recurse_x::Name::from_ascii(&url.host).is_ok()))
}

fn valid_digest(hash: &str, size: u32) -> bool {
    (1..=536_870_912).contains(&size)
        && hash.len() == 64
        && hash
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn valid_encodings(ep: &Episode, files: &[VideoEncoding]) -> bool {
    let mut sizes = HashSet::new();
    let mut hashes = HashSet::new();
    let mut urls = HashSet::new();
    (2..=16).contains(&files.len())
        && files.iter().all(|f| {
            (1..=16384).contains(&f.width)
                && (1..=16384).contains(&f.height)
                && valid_address(&f.url)
                && valid_digest(&f.sha256, f.bytes)
                && sizes.insert((f.width, f.height))
                && hashes.insert(&f.sha256)
                && urls.insert(&f.url)
        })
        && files.iter().any(|f| {
            f.url == ep.url && Some(&f.sha256) == ep.sha256.as_ref() && Some(f.bytes) == ep.bytes
        })
}

pub fn parse_catalog(bytes: Vec<u8>) -> Result<Vec<Drama>, String> {
    if bytes.len() > MAX_CATALOG_BYTES {
        return Err("size".into());
    }
    let catalog: Catalog = nextjson::nextdecode(&bytes).map_err(|_| "json")?;
    if catalog.version != 1 || catalog.dramas.len() > 1000 {
        return Err("catalog".into());
    }
    let mut ids = HashSet::new();
    for drama in &catalog.dramas {
        if !valid_text(&drama.id, 96)
            || !ids.insert(&drama.id)
            || !valid_text(&drama.title, 384)
            || drama.tags.is_empty()
            || drama.tags.len() > 12
            || drama.tags.iter().any(|s| !valid_text(s, 72))
            || drama.tags.iter().collect::<HashSet<_>>().len() != drama.tags.len()
            || drama.cover.as_ref().is_some_and(|s| !valid_address(s))
            || drama.episodes.is_empty()
            || drama.episodes.len() > 2000
            || drama
                .episode_count
                .is_some_and(|total| total < drama.episodes.len() as u32)
        {
            return Err("drama".into());
        }
        let mut episodes = HashSet::new();
        let published = drama
            .published_ids
            .as_ref()
            .map(|ids| ids.iter().collect::<HashSet<_>>());
        if let (Some(ids), Some(unique)) = (&drama.published_ids, &published)
            && (Some(ids.len() as u32) != drama.episode_count
                || unique.len() != ids.len()
                || ids.iter().any(|id| !valid_text(id, 96)))
        {
            return Err("episode list".into());
        }
        let series_page = format!("https://hongguoduanju.com/player/{}", drama.id);
        for ep in &drama.episodes {
            let breaks = ep.ad_breaks.as_deref().unwrap_or_default();
            if !valid_text(&ep.id, 96)
                || !episodes.insert(&ep.id)
                || published.as_ref().is_some_and(|ids| !ids.contains(&ep.id))
                || !valid_text(&ep.title, 384)
                || !valid_address(&ep.url)
                || ep.mirrors.as_ref().is_some_and(|urls| {
                    urls.len() > 3
                        || urls.iter().any(|url| !valid_address(url) || url == &ep.url)
                        || urls.iter().collect::<HashSet<_>>().len() != urls.len()
                })
                || match (&ep.sha256, ep.bytes) {
                    (Some(hash), Some(size)) => !valid_digest(hash, size),
                    (None, None) => false,
                    _ => true,
                }
                || ep
                    .encodings
                    .as_ref()
                    .is_some_and(|files| !valid_encodings(ep, files))
                || ep.page.as_ref().is_some_and(|page| {
                    !valid_address(page)
                        || (page != &series_page && page != &format!("{series_page}/{}", ep.id))
                })
                || breaks.len() > 64
                || breaks.iter().any(|b| b.start_ms >= b.end_ms)
                || breaks
                    .windows(2)
                    .any(|pair| pair[0].end_ms >= pair[1].start_ms)
            {
                return Err("episode".into());
            }
        }
    }
    Ok(catalog.dramas)
}

fn validate_history(entries: &[Progress]) -> Result<(), String> {
    let mut ids = HashSet::new();
    if entries.len() > HISTORY_LIMIT
        || entries.iter().any(|p| {
            !valid_text(&p.drama, 96)
                || !valid_text(&p.episode, 96)
                || !ids.insert((&p.drama, &p.episode))
                || p.position_ms > p.duration_ms
                || p.watched_ms > p.duration_ms
        })
    {
        return Err("history".into());
    }
    Ok(())
}

pub fn pack_history(entries: Vec<Progress>) -> Result<Vec<u8>, String> {
    validate_history(&entries)?;
    let data = rustbinary::options()
        .with_limit(MAX_HISTORY_BYTES as u64)
        .with_compact_format()
        .serialize(&entries)
        .map_err(|_| "encode")?;
    let mut frame = b"SW01".to_vec();
    frame.extend(data);
    Ok(frame)
}

pub fn unpack_history(bytes: Vec<u8>) -> Result<Vec<Progress>, String> {
    if bytes.len() > MAX_HISTORY_BYTES || !bytes.starts_with(b"SW01") {
        return Err("version".into());
    }
    let entries: Vec<Progress> = rustbinary::options()
        .with_limit(MAX_HISTORY_BYTES as u64)
        .with_collection_limit(HISTORY_LIMIT as u64)
        .with_compact_format()
        .deserialize(&bytes[4..])
        .map_err(|_| "decode")?;
    validate_history(&entries)?;
    Ok(entries)
}

pub fn recommendations(
    candidates: Vec<Candidate>,
    entries: Vec<Progress>,
    now: u32,
) -> Vec<String> {
    let mut evidence: HashMap<&str, f64> = HashMap::new();
    let mut seen = HashSet::new();
    let half_life = Duration::days(21).as_seconds_f64();
    for p in &entries {
        if p.watched_ms == 0 || p.duration_ms == 0 {
            continue;
        }
        seen.insert(p.drama.as_str());
        let fraction = f64::from(p.watched_ms.min(p.duration_ms))
            / (f64::from(p.duration_ms) + WATCH_PRIOR_MS);
        let age = f64::from(now.saturating_sub(p.updated));
        *evidence.entry(&p.drama).or_default() += fraction * (-age / half_life).exp2();
    }
    let mut weights: HashMap<&str, f64> = HashMap::new();
    for c in &candidates {
        if let Some(mass) = evidence.get(c.id.as_str()) {
            for tag in &c.tags {
                *weights.entry(tag).or_default() += mass / c.tags.len() as f64;
            }
        }
    }
    let mut scores: Vec<_> = candidates
        .iter()
        .enumerate()
        .filter(|(_, c)| !seen.contains(c.id.as_str()))
        .map(|(index, c)| {
            let score = c
                .tags
                .iter()
                .map(|tag| 1.0 + weights.get(tag.as_str()).copied().unwrap_or_default())
                .sum::<f64>()
                / c.tags.len().max(1) as f64;
            (score, index)
        })
        .collect();
    scores.sort_unstable_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)));
    scores
        .into_iter()
        .map(|(_, i)| candidates[i].id.clone())
        .collect()
}
