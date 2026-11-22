# Your music

Put the music you want while reading in this folder, or straight in
`assets/sounds/`, then build the app again. Each book starts one of your tracks at random and plays on through
them; while reading, tap the screen for previous, pause and next.

- **Formats:** MP3, M4A, AAC, OGG, Opus, WAV or FLAC.
- **Size:** every track is packed into the app, so prefer compressed files.
  128 kbps MP3 is about 1 MB a minute and sounds the same as 320 kbps under
  narration (the bundled tracks were re-encoded so: 13 MB became 5 MB). To
  re-encode one: `ffmpeg -i in.mp3 -map_metadata 0 -b:a 128k out.mp3`
- **Names:** name a file `Artist - Title.mp3` and the player shows
  "Title · Artist"; a leading track number and a note in brackets at the end
  are dropped (`Lukrembo - Jay (freetouse.com).mp3` shows "Jay · Lukrembo").
- **Rights:** only add music you're allowed to use in an app you share.

Credit the music in `../CREDITS.md` (the app shows it on its licences page).
