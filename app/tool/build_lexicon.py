"""Builds app lexicon assets: Zipf frequencies (wordfreq) and a WordNet subset."""
import gzip, json, re, sys
from wordfreq import top_n_list, zipf_frequency
import nltk
nltk.data.path.insert(0, sys.argv[1])
from nltk.corpus import wordnet as wn

out = sys.argv[2]
word_re = re.compile(r"^[a-z][a-z'\-]*$")
words = [w for w in top_n_list('en', 80000) if word_re.match(w)]
zipf = {w: round(zipf_frequency(w, 'en'), 1) for w in words}
with gzip.open(f"{out}/zipf.tsv.gz", "wt", encoding="utf-8") as f:
    for w, z in zipf.items():
        f.write(f"{w}\t{z}\n")

pos_name = {'n': 'noun', 'v': 'verb', 'a': 'adjective', 's': 'adjective', 'r': 'adverb'}
entries = {}
for lemma in sorted(set(l.lower() for l in wn.all_lemma_names())):
    if not word_re.match(lemma):
        continue
    z = zipf_frequency(lemma, 'en')
    # Keep words a reader might look up: skip the most common (z >= 5.2) and unseen ones.
    if z >= 5.2 or z < 1.0:
        continue
    senses = []
    for syn in wn.synsets(lemma)[:3]:
        d = syn.definition()
        ex = syn.examples()[:1]
        senses.append([pos_name.get(syn.pos(), syn.pos()), d] + ([ex[0]] if ex else []))
    if senses:
        entries[lemma] = senses
with gzip.open(f"{out}/wordnet.json.gz", "wt", encoding="utf-8") as f:
    json.dump(entries, f, separators=(",", ":"))
print(len(zipf), "freq words;", len(entries), "dictionary entries")
