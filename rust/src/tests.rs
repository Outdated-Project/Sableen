use crate::api::library::*;

fn watch() -> Progress {
    Progress {
        drama: "seen".into(),
        episode: "ep1".into(),
        position_ms: 900,
        duration_ms: 1000,
        watched_ms: 120,
        updated: 1_700_000_000,
        completed: false,
    }
}

#[test]
fn history_roundtrip_and_invalid_frames() {
    let p = watch();
    let frame = pack_history(vec![p.clone()]).unwrap();
    assert_eq!(unpack_history(frame.clone()).unwrap(), vec![p.clone()]);
    for n in 0..frame.len() {
        assert!(unpack_history(frame[..n].to_vec()).is_err());
    }
    assert!(pack_history(vec![p.clone(), p]).is_err());
}

#[test]
fn eligibility_ties_and_genre_affinity() {
    let catalog = || {
        [
            ("seen", "A"),
            ("other", "B"),
            ("match1", "A"),
            ("match2", "A"),
        ]
        .into_iter()
        .map(|(id, tag)| Candidate {
            id: id.into(),
            tags: vec![tag.into()],
        })
        .collect()
    };
    assert_eq!(
        recommendations(catalog(), vec![], 0),
        ["seen", "other", "match1", "match2"]
    );
    assert_eq!(
        recommendations(catalog(), vec![watch()], 1_700_000_000),
        ["match1", "match2", "other"]
    );
}

#[test]
fn catalog_rejects_ambiguous_ids_and_non_https() {
    let drama = r#"{"id":"s","title":"剧","tags":["A"],"episodes":[{"id":"e","title":"一","url":"https://cdn.example.org/v.mp4"}]}"#;
    let input = |rows: &str| format!(r#"{{"version":1,"dramas":[{rows}]}}"#).into_bytes();
    assert_eq!(parse_catalog(input(drama)).unwrap().len(), 1);
    let linked =
        |page: &str| input(&drama.replace("\"url\":", &format!("\"page\":\"{page}\",\"url\":")));
    let page = "https://hongguoduanju.com/player/s/e";
    assert_eq!(
        parse_catalog(linked(page)).unwrap()[0].episodes[0]
            .page
            .as_deref(),
        Some(page)
    );
    assert!(parse_catalog(linked("https://hongguoduanju.com/player/s/other")).is_err());
    assert!(parse_catalog(input(&format!("{drama},{drama}"))).is_err());
    let marked = |ranges: &str| {
        input(&drama.replace("\"url\":", &format!("\"ad_breaks\":{ranges},\"url\":")))
    };
    assert!(parse_catalog(marked(r#"[{"start_ms":0,"end_ms":50}]"#)).is_ok());
    assert!(parse_catalog(marked(r#"[{"start_ms":10,"end_ms":5}]"#)).is_err());
    assert!(
        parse_catalog(marked(
            r#"[{"start_ms":2,"end_ms":8},{"start_ms":5,"end_ms":10}]"#
        ))
        .is_err()
    );
    for url in [
        "file:///etc/test",
        "https://x@example.org/v",
        "https://invalid_host/v",
        "https://good.org\\@bad.org/v",
    ] {
        assert!(!valid_address(url));
    }
}

#[test]
fn catalog_preserves_every_distinct_verified_resolution() {
    let encodings: Vec<_> = (1..=17)
        .map(|i| format!(r#"{{"width":{},"height":{},"url":"https://cdn.example.org/{i}.mp4","bytes":123,"sha256":"{i:064x}"}}"#, i * 32, i * 18))
        .collect();
    let files = encodings.join(",");
    let json = format!(
        r#"{{"version":1,"dramas":[{{"id":"s","title":"S","tags":["A"],"episodes":[{{"id":"e","title":"E","url":"https://cdn.example.org/1.mp4","bytes":123,"sha256":"{:064x}","encodings":[{files}]}}]}}]}}"#,
        1
    );
    let catalog = parse_catalog(json.clone().into_bytes()).unwrap();
    assert_eq!(catalog[0].episodes[0].encodings.as_ref().unwrap().len(), 17);
    assert!(parse_catalog(json.replace("\"width\":32,", "\"width\":0,").into_bytes()).is_err());
}

#[test]
fn ranking_uses_watched_time_and_half_life() {
    let old = Progress {
        watched_ms: 1000,
        ..watch()
    };
    let now = old.updated + 21 * 86400;
    let recent = Progress {
        drama: "recent".into(),
        updated: now,
        watched_ms: 600,
        position_ms: 0,
        ..watch()
    };
    let candidates = [
        ("seen", "a"),
        ("recent", "b"),
        ("older-genre", "a"),
        ("newer-genre", "b"),
    ]
    .into_iter()
    .map(|(id, tag)| Candidate {
        id: id.into(),
        tags: vec![tag.into()],
    })
    .collect();
    assert_eq!(
        recommendations(candidates, vec![old, recent], now),
        ["newer-genre", "older-genre"]
    );
}

#[test]
fn short_previews_supply_less_evidence_than_sustained_viewing() {
    let preview = Progress {
        drama: "preview".into(),
        watched_ms: 10_000,
        duration_ms: 10_000,
        ..watch()
    };
    let episode = Progress {
        drama: "episode".into(),
        watched_ms: 120_000,
        duration_ms: 240_000,
        ..watch()
    };
    let now = episode.updated;
    let candidates = [
        ("preview", "A"),
        ("episode", "B"),
        ("more-A", "A"),
        ("more-B", "B"),
    ]
    .into_iter()
    .map(|(id, genre)| Candidate {
        id: id.into(),
        tags: vec![genre.into()],
    })
    .collect();
    assert_eq!(
        recommendations(candidates, vec![preview, episode], now),
        ["more-B", "more-A"]
    );
}

#[test]
fn bundled_catalogs_have_unique_ids_and_valid_media() {
    let mut ids = std::collections::HashSet::new();
    for data in [
        include_bytes!("../../assets/catalogs/hongguo.json").as_slice(),
        include_bytes!("../../assets/catalogs/comic.json").as_slice(),
    ] {
        let titles = parse_catalog(data.to_vec()).unwrap();
        assert!(!titles.is_empty());
        for drama in titles {
            assert!(
                drama
                    .episode_count
                    .is_some_and(|total| total >= drama.episodes.len() as u32)
            );
            let series_page = format!("https://hongguoduanju.com/player/{}", drama.id);
            assert!(ids.insert(drama.id));
            for episode in drama.episodes {
                assert!(valid_address(&episode.url));
                assert!(episode.page.is_some_and(|p| p.starts_with(&series_page)));
                assert!(episode.sha256.is_some() && episode.bytes.is_some());
                assert!(episode.duration_ms.is_some_and(|ms| ms > 0));
                assert!(episode.listed_ms.is_some_and(|ms| ms > 0));
            }
        }
    }
}
