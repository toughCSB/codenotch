//! Two deliberately separate GitHub Release checks.
//!
//! The original `vinzdg/codenotch` check is informational only: its result contains no asset URL
//! and therefore has no path to the installer. This fork's releases are a second check and the only
//! source `download_and_launch` accepts. No signing keys, no `latest.json` manifest, no auto-apply:
//! this fork's releases are still a
//! human building `cargo tauri build` and dragging the installer onto a GitHub release by hand
//! (see windows/README.md), so a full `tauri-plugin-updater` pipeline would be new infrastructure
//! this app does not otherwise need. Instead: ask GitHub's public releases API whether a newer
//! `windows-vX.Y.Z` tag exists, and if the user clicks the button, download that release's
//! installer and launch it — the installer (and the user, who sees its window) does the rest.

use serde::Serialize;
use std::io::Read;
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

const FORK_REPO: &str = "toughCSB/codenotch";
const UPSTREAM_REPO: &str = "vinzdg/codenotch";
/// This fork tags its Windows releases separately from the Mac app's plain `vX.Y.Z` ones.
const TAG_PREFIX: &str = "windows-v";

#[derive(Clone, Serialize, Default)]
pub struct UpdateInfo {
    pub checking: bool,
    pub checked: bool,
    pub current: String,
    pub latest: String,
    pub available: bool,
    /// The release page, for "what changed" — opened in a browser, never auto-read.
    pub html_url: String,
    pub asset_url: String,
    pub asset_name: String,
    pub error: String,
}

static LAST: Mutex<Option<UpdateInfo>> = Mutex::new(None);

/// The original app's latest release. Deliberately no downloadable asset fields: upstream can be
/// inspected from this fork, but can never be installed over it.
#[derive(Clone, Serialize, Default)]
pub struct UpstreamInfo {
    pub checking: bool,
    pub checked: bool,
    pub latest: String,
    pub html_url: String,
    pub error: String,
}

static UPSTREAM_LAST: Mutex<Option<UpstreamInfo>> = Mutex::new(None);

pub fn last() -> UpdateInfo {
    LAST.lock().unwrap().clone().unwrap_or_default()
}

pub fn upstream_last() -> UpstreamInfo {
    UPSTREAM_LAST.lock().unwrap().clone().unwrap_or_default()
}

#[derive(serde::Deserialize)]
struct GhRelease {
    tag_name: String,
    html_url: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
    #[serde(default)]
    assets: Vec<GhAsset>,
}

#[derive(serde::Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

/// `1.2.10` beats `1.2.9`: each dot-separated run of leading digits compares as a number, not as
/// text, so a two-digit patch release is never mistaken for older than a one-digit one.
fn newer(a: &str, b: &str) -> bool {
    fn parts(s: &str) -> Vec<u64> {
        s.split('.')
            .map(|p| p.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().unwrap_or(0))
            .collect()
    }
    let (pa, pb) = (parts(a), parts(b));
    for i in 0..pa.len().max(pb.len()) {
        let (x, y) = (pa.get(i).copied().unwrap_or(0), pb.get(i).copied().unwrap_or(0));
        if x != y {
            return x > y;
        }
    }
    false
}

/// This fork's releases page mixes Windows (`windows-vX.Y.Z`) and Mac (`vX.Y.Z`) tags in one list,
/// sorted by creation time — a burst of Mac releases can push the last Windows one off a single
/// page. Walked a few pages deep rather than one, so a real Windows release is not missed just
/// because it is not the newest release in the whole repo.
const MAX_PAGES: u32 = 4;
const PER_PAGE: u32 = 30;

fn fetch_latest() -> Result<(String, String, Option<GhAsset>), String> {
    let mut last_err = "no Windows release found".to_string();
    for page in 1..=MAX_PAGES {
        let url = format!("https://api.github.com/repos/{FORK_REPO}/releases?per_page={PER_PAGE}&page={page}");
        let resp = ureq::get(&url)
            .set("User-Agent", concat!("codenotch/", env!("CARGO_PKG_VERSION"), " (Windows)"))
            .set("Accept", "application/vnd.github+json")
            .timeout(Duration::from_secs(15))
            .call()
            .map_err(|e| format!("{e}"))?;
        let releases: Vec<GhRelease> = resp.into_json().map_err(|e| format!("parse: {e}"))?;
        if releases.is_empty() {
            break; // fewer releases than MAX_PAGES * PER_PAGE: nothing further to fetch
        }
        if let Some(rel) = releases.into_iter().find(|r| !r.draft && !r.prerelease && r.tag_name.starts_with(TAG_PREFIX)) {
            let asset = rel
                .assets
                .into_iter()
                .find(|a| a.name.to_lowercase().ends_with("-setup.exe") || a.name.to_lowercase().ends_with(".exe"));
            return Ok((rel.tag_name, rel.html_url, asset));
        }
        last_err = format!("no Windows release found in the {} most recent releases", page * PER_PAGE);
    }
    Err(last_err)
}

fn fetch_upstream_latest() -> Result<(String, String), String> {
    let url = format!("https://api.github.com/repos/{UPSTREAM_REPO}/releases/latest");
    let rel: GhRelease = ureq::get(&url)
        .set("User-Agent", concat!("codenotch/", env!("CARGO_PKG_VERSION"), " (Windows)"))
        .set("Accept", "application/vnd.github+json")
        .timeout(Duration::from_secs(15))
        .call()
        .map_err(|e| format!("{e}"))?
        .into_json()
        .map_err(|e| format!("parse: {e}"))?;
    if rel.draft || rel.prerelease {
        return Err("the latest upstream release is not a stable release".into());
    }
    Ok((rel.tag_name.trim_start_matches('v').to_string(), rel.html_url))
}

/// Reports the original project's latest release. There is intentionally no install counterpart.
pub fn check_upstream(app: &AppHandle) -> UpstreamInfo {
    let mut info = UpstreamInfo { checking: true, ..Default::default() };
    *UPSTREAM_LAST.lock().unwrap() = Some(info.clone());
    let _ = app.emit("upstream_update_info", &info);
    match fetch_upstream_latest() {
        Ok((latest, html_url)) => {
            info.latest = latest;
            info.html_url = html_url;
        }
        Err(error) => info.error = error,
    }
    info.checking = false;
    info.checked = true;
    *UPSTREAM_LAST.lock().unwrap() = Some(info.clone());
    let _ = app.emit("upstream_update_info", &info);
    info
}

/// Runs the check inline (on whatever thread calls it — callers hop to a background thread first)
/// and both returns and broadcasts the result, so the settings window updates whether it asked or
/// merely has the page open when a background check lands.
pub fn check(app: &AppHandle) -> UpdateInfo {
    let current = env!("CARGO_PKG_VERSION").to_string();
    let mut info = UpdateInfo { checking: true, current: current.clone(), ..Default::default() };
    *LAST.lock().unwrap() = Some(info.clone());
    let _ = app.emit("update_info", &info);

    match fetch_latest() {
        Ok((tag, html_url, asset)) => {
            let latest = tag.strip_prefix(TAG_PREFIX).unwrap_or(&tag).to_string();
            info.available = newer(&latest, &current);
            info.latest = latest;
            info.html_url = html_url;
            if let Some(a) = asset {
                info.asset_url = a.browser_download_url;
                info.asset_name = a.name;
            }
        }
        Err(e) => info.error = e,
    }
    info.checking = false;
    info.checked = true;
    *LAST.lock().unwrap() = Some(info.clone());
    let _ = app.emit("update_info", &info);
    info
}

/// A background check once shortly after launch — quiet unless there is something to say; the
/// settings window's own "Check now" button reruns `check` directly and awaits it.
pub fn start(app: AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(20));
        check(&app);
        check_upstream(&app);
    });
}

/// Downloads the release's installer to a temp file and launches it, then quits Codenotch so the
/// installer is not fighting the running exe for its own file lock. The installer's own window is
/// what the user watches from here — nothing here runs silently or without that visible step.
pub fn download_and_launch(app: &AppHandle) -> Result<(), String> {
    // Never accept a URL from the page. Only the asset returned by this fork's last successful
    // release check may become executable; the original-project check has no asset field at all.
    let info = last();
    if !info.available || info.asset_url.is_empty() {
        return Err("no installable update for this Windows app was checked".into());
    }
    let resp = ureq::get(&info.asset_url)
        .set("User-Agent", concat!("codenotch/", env!("CARGO_PKG_VERSION"), " (Windows)"))
        .timeout(Duration::from_secs(120))
        .call()
        .map_err(|e| format!("download failed: {e}"))?;
    let mut bytes = Vec::new();
    resp.into_reader().read_to_end(&mut bytes).map_err(|e| format!("download failed: {e}"))?;
    if bytes.is_empty() {
        return Err("downloaded file is empty".into());
    }
    let name = if info.asset_name.is_empty() { "Provider-Monitor-Setup.exe" } else { &info.asset_name };
    let path = std::env::temp_dir().join(name);
    std::fs::write(&path, &bytes).map_err(|e| format!("could not save installer: {e}"))?;
    std::process::Command::new(&path)
        .spawn()
        .map_err(|e| format!("could not start the installer: {e}"))?;
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(400));
        app.exit(0);
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::newer;

    #[test]
    fn a_higher_version_is_newer() {
        assert!(newer("0.4.0", "0.3.0"));
        assert!(newer("0.3.1", "0.3.0"));
        assert!(newer("1.0.0", "0.9.9"));
    }

    #[test]
    fn the_same_or_an_older_version_is_not_newer() {
        assert!(!newer("0.3.0", "0.3.0"));
        assert!(!newer("0.2.9", "0.3.0"));
    }

    /// `1.2.10` must not be read as older than `1.2.9` by comparing the strings byte for byte.
    #[test]
    fn a_two_digit_component_is_compared_numerically() {
        assert!(newer("1.2.10", "1.2.9"));
    }

    /// Real production data (windows-v0.3.0, api.github.com/repos/toughCSB/codenotch/releases):
    /// a same-version release must not be reported as an update.
    #[test]
    fn the_current_shipped_release_is_not_flagged_as_an_update() {
        assert!(!newer("0.3.0", env!("CARGO_PKG_VERSION")));
    }
}
