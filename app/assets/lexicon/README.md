# Lexicon assets

| File | Source | License |
|---|---|---|
| `zipf.tsv.gz` | Zipf word frequencies from [wordfreq](https://github.com/rspeer/wordfreq) (top 80k English words) | wordfreq data: CC BY-SA 4.0 (attribution required; derived data shared under the same license) |
| `wordnet.json.gz` | Up to 3 senses per lemma from [WordNet 3.0](https://wordnet.princeton.edu/) for words with Zipf 1.0–5.2 | WordNet License (see `WORDNET_LICENSE`) |

Regenerate with `tool/build_lexicon.py` (needs `pip install wordfreq nltk` and the NLTK WordNet corpus).
