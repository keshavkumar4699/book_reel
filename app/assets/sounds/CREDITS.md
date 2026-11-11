# Scene sounds: sources and licences

Each scene plays a mix of these loops (see `lib/services/scene_sound.dart`).
The recordings come from the sound set of the open-source app
[Blanket](https://github.com/rafaelmardojai/blanket), which lists each sound's
origin and licence in its `SOUNDS_LICENSING.md`. "Edited by Porrumentzio" means
Blanket's editor trimmed the original and made it loop.

| File | Sound | Author | Source | Licence |
|---|---|---|---|---|
| `birds.ogg` | Birds | kvgarlic (edited by Porrumentzio) | [freesound.org/s/156826](https://freesound.org/people/kvgarlic/sounds/156826/) | CC0 1.0 (public domain dedication) |
| `wind.ogg` | Wind | felix.blume (edited by Porrumentzio) | [freesound.org/s/217506](https://freesound.org/people/felix.blume/sounds/217506/) | CC0 1.0 |
| `rain.ogg` | Rain | alex36917 (edited by Porrumentzio) | [freesound.org/s/524605](https://freesound.org/people/alex36917/sounds/524605/) | CC BY (Creative Commons Attribution) |
| `waves.ogg` | Waves | Luftrum (edited by Porrumentzio) | [freesound.org/s/48412](https://freesound.org/people/Luftrum/sounds/48412/) | CC BY |
| `city.ogg` | City | gezortenplotz (edited by Porrumentzio) | [freesound.org/s/44796](https://freesound.org/people/gezortenplotz/sounds/44796/) | CC BY |
| `cafe.ogg` | Restaurant Ambiance | stephan | [soundbible.com/1664](https://soundbible.com/1664-Restaurant-Ambiance.html) | Public domain |
| `fireplace.ogg` | Fireplace | ezwa | [soundbible.com/1543](https://soundbible.com/1543-Fireplace.html) | Public domain |
| `crickets.ogg` | Crickets Chirping At Night | Lisa Redfern | [soundbible.com/2083](https://soundbible.com/2083-Crickets-Chirping-At-Night.html) | Public domain |
| `brown-noise.ogg` | Brown noise | BookReel (generated) | `tool/build_scene_sounds.py` | Ours, no restrictions |

The exact CC BY version for each recording is stated on its source page.

**Changes made for BookReel** (`tool/build_scene_sounds.py`): every file was
levelled to the same loudness and re-encoded as Ogg Vorbis. `cafe`, `wind`,
`crickets` and `fireplace` were also trimmed and given a crossfaded loop
point, and `fireplace` was softly limited to tame its loudest crackles.

The CC BY recordings require credit. It is given here and on the app's
licences page (Settings → About → Licences).
