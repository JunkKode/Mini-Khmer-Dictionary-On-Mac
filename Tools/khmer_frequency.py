#!/usr/bin/env python3
"""How often each headword is actually used inside the dictionary's definitions.

Khmer is written without spaces, so counting raw substrings would credit កម
every time កម្ម or កមករ appears. Instead the corpus is segmented greedily —
at each position the longest headword that fits wins, and scanning resumes
after it — which approximates word boundaries well enough to tell a common word
from a rare one.

The app uses the result only to break ties between romanized candidates that
are already equally close phonetically, so imperfect segmentation is cheap.
"""


def count_word_uses(patterns, texts):
    """Return occurrence counts parallel to `patterns`, by longest-match scan."""
    children = [{}]
    word_id = [-1]

    for pattern_id, pattern in enumerate(patterns):
        node = 0
        for char in pattern:
            nxt = children[node].get(char)
            if nxt is None:
                nxt = len(children)
                children.append({})
                word_id.append(-1)
                children[node][char] = nxt
            node = nxt
        if node != 0:
            word_id[node] = pattern_id

    counts = [0] * len(patterns)
    for text in texts:
        length = len(text)
        start = 0
        while start < length:
            node = 0
            best = -1
            best_length = 0
            position = start
            while position < length:
                nxt = children[node].get(text[position])
                if nxt is None:
                    break
                node = nxt
                position += 1
                if word_id[node] >= 0:
                    best = word_id[node]
                    best_length = position - start
            if best >= 0:
                counts[best] += 1
                start += best_length
            else:
                start += 1
    return counts
