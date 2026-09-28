Lyrimuse upstream: https://github.com/Yudaotor/lyrimuse
Revision: e41263c717cdfa6b9aea8e73ccc97f0c3188a46f
License: GPL-3.0 (full text in LICENSE).

Model/LyrimuseKaraoke.swift retains upstream KaraokeFill calculations.
The timed-word renderer and lyric provider adapters are iOS adaptations of
Lyrimuse's word timing, gradient/rise behavior and collector source protocols.
macOS windows, media monitoring, and collector processes are not included.
This integration does not relicense upstream code as part of a proprietary SDK.

Implemented source paths: NetEase (YRC/LRC), QQ (LRC), Kugou (KRC/LRC),
Musixmatch (Richsync/LRC), LRCLIB, Kuwo, Migu, LyricFind via YouTube Music,
and AMLL TTML enrichment using matched NetEase/QQ song IDs.
QQ's authenticated collector session and proprietary QRC cipher are not ported;
QQ word timing currently comes from AMLL when available. Remote endpoints can
reject requests or have no timed lyrics for a recording; these are fallbacks,
not promises of availability. Matching/scoring is a conservative iOS adaptation,
not the complete Go collector resolver.
