#!/usr/bin/env python3
"""Approximate Khmer -> Latin transcription, plus the fuzzy key used for search.

This is the source of truth for how romanized queries match Khmer headwords.
`fuzzy_key` is mirrored byte-for-byte by `RomanizedSearch.fuzzyKey(_:)` in the
app; the app applies it to what the user types, this script applies it to every
headword at build time. If you change one, change the other.

The transcription is deliberately approximate. Khmer vowel values depend on the
consonant series, clusters have exceptions, and the fuzzy key throws most vowel
detail away anyway -- being roughly right is enough to rank matches well.
"""

import re
import unicodedata

# base romanisation and consonant series (1 = a-series, 2 = o-series)
CONSONANTS = {
    "ក": ("k", 1), "ខ": ("kh", 1), "គ": ("k", 2), "ឃ": ("kh", 2), "ង": ("ng", 2),
    "ច": ("ch", 1), "ឆ": ("chh", 1), "ជ": ("ch", 2), "ឈ": ("chh", 2), "ញ": ("nh", 2),
    "ដ": ("d", 1), "ឋ": ("th", 1), "ឌ": ("d", 2), "ឍ": ("th", 2), "ណ": ("n", 1),
    "ត": ("t", 1), "ថ": ("th", 1), "ទ": ("t", 2), "ធ": ("th", 2), "ន": ("n", 2),
    "ប": ("b", 1), "ផ": ("ph", 1), "ព": ("p", 2), "ភ": ("ph", 2), "ម": ("m", 2),
    "យ": ("y", 2), "រ": ("r", 2), "ល": ("l", 2), "វ": ("v", 2),
    "ស": ("s", 1), "ហ": ("h", 1), "ឡ": ("l", 1), "អ": ("", 1),
    "ឝ": ("s", 1), "ឞ": ("s", 1),
}

# finals that are pronounced differently from their onset value
FINALS = {"ស": "h", "ហ": "h", "ជ": "ch", "ព": "p", "ប": "p", "ដ": "t", "ឌ": "t"}

INDEPENDENT = {
    "ឥ": "e", "ឦ": "ei", "ឧ": "o", "ឨ": "o", "ឩ": "ou", "ឪ": "au",
    "ឫ": "ru", "ឬ": "ru", "ឭ": "lu", "ឮ": "lu", "ឯ": "ae", "ឰ": "ai",
    "ឱ": "ao", "ឲ": "ao", "ឳ": "au",
}

# vowel sign sequence -> (a-series reading, o-series reading)
VOWELS = {
    "": ("a", "o"),
    "ា": ("a", "ea"), "ិ": ("e", "i"), "ី": ("ei", "i"),
    "ឹ": ("oe", "eu"), "ឺ": ("oe", "eu"), "ុ": ("o", "u"), "ូ": ("ou", "u"),
    "ួ": ("uo", "uo"), "ើ": ("aeu", "eu"), "ឿ": ("oea", "oea"), "ៀ": ("ie", "ie"),
    "េ": ("e", "e"), "ែ": ("ae", "e"), "ៃ": ("ai", "ey"),
    "ោ": ("ao", "ou"), "ៅ": ("au", "ou"),
    "ំ": ("am", "um"), "ុំ": ("om", "um"), "ាំ": ("am", "oam"),
    "ះ": ("ah", "eah"), "ិះ": ("eh", "ih"), "ុះ": ("oh", "uh"),
    "េះ": ("eh", "eh"), "ោះ": ("aoh", "uoh"), "ាះ": ("ah", "eah"),
    "័": ("a", "ea"), "់": ("a", "o"),
}

VOWEL_SIGNS = set("ាិីឹឺុូួើឿៀេែៃោៅំះ់័")
COENG = "្"
MUSIKATOAN = "៉"   # o-series consonant read as a-series
TRIISAP = "៊"      # a-series consonant read as o-series
TOANDAKHIAT = "៍"  # silences the consonant it sits on
SHIFTERS = (MUSIKATOAN, TRIISAP)


def romanize(word: str) -> str:
    """Transcribe a Khmer headword into readable Latin letters."""
    chars = list(word)
    count = len(chars)
    index = 0
    syllables = []

    while index < count:
        char = chars[index]

        if char in INDEPENDENT:
            syllables.append(INDEPENDENT[char])
            index += 1
            continue

        if char not in CONSONANTS:
            index += 1
            continue

        cluster = [char]
        index += 1
        series_override = None

        def absorb_shifters(position):
            nonlocal series_override
            while position < count and chars[position] in SHIFTERS:
                series_override = 1 if chars[position] == MUSIKATOAN else 2
                position += 1
            return position

        index = absorb_shifters(index)

        while index + 1 < count and chars[index] == COENG and chars[index + 1] in CONSONANTS:
            cluster.append(chars[index + 1])
            index += 2
            index = absorb_shifters(index)

        if index < count and chars[index] == TOANDAKHIAT:  # whole cluster is silent
            index += 1
            continue

        signs = ""
        while index < count and chars[index] in VOWEL_SIGNS:
            signs += chars[index]
            index += 1

        series = series_override or CONSONANTS[cluster[0]][1]
        onset = "".join(CONSONANTS[consonant][0] for consonant in cluster)
        vowel = lookup_vowel(signs, series)

        coda = ""
        if index < count and chars[index] in CONSONANTS and is_final(chars, index, count):
            coda = FINALS.get(chars[index], CONSONANTS[chars[index]][0])
            index += 1
            if index < count and chars[index] in ("់", TOANDAKHIAT):
                index += 1

        syllables.append(onset + vowel + coda)

    return "".join(syllables)


def lookup_vowel(signs: str, series: int) -> str:
    if signs in VOWELS:
        return VOWELS[signs][series - 1]
    stripped = signs.replace("់", "")
    if stripped in VOWELS:
        return VOWELS[stripped][series - 1]
    for sign in signs:  # fall back to the first sign we recognise
        if sign in VOWELS:
            return VOWELS[sign][series - 1]
    return VOWELS[""][series - 1]


def is_final(chars, index: int, count: int) -> bool:
    """A consonant is a coda when nothing after it starts a new syllable."""
    following = index + 1
    if following >= count:
        return True
    nxt = chars[following]
    if nxt in ("់", TOANDAKHIAT, "ៗ", "។"):
        return True
    return False


# ---------------------------------------------------------------------------
# fuzzy key -- mirrored in Swift by RomanizedSearch.fuzzyKey(_:)
# ---------------------------------------------------------------------------

DIGRAPHS = (("chh", "c"), ("ch", "c"), ("kh", "k"), ("ph", "p"), ("th", "t"), ("nh", "n"))
VOICING = (("b", "p"), ("d", "t"), ("g", "k"), ("j", "c"), ("z", "s"),
           ("f", "p"), ("w", "v"), ("q", "k"), ("x", "k"))


def compare_key(value: str) -> str:
    """Fold away spelling choices that carry no sound difference.

    Aspiration (`kh`/`k`) and voicing (`d`/`t`, `b`/`p`) are written every which
    way by people typing Khmer in Latin letters, so both are collapsed. Vowels
    are kept, which makes this the key used to rank matches against each other.
    """
    text = unicodedata.normalize("NFD", value.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^a-z]", "", text)

    for source, target in DIGRAPHS:
        text = text.replace(source, target)
    text = text.replace("ng", "N")  # protect the velar nasal from g -> k
    for source, target in VOICING:
        text = text.replace(source, target)
    return text.replace("N", "ng")


def fuzzy_key(value: str) -> str:
    """Reduce a romanisation to the skeleton used to *find* matches.

    On top of `compare_key`, vowel quality is discarded entirely -- `domlai` and
    `tomlai` and `tumley` all collapse together. A leading `y` is kept as a
    consonant so that យ- words (`yon`) do not collide with vowel-initial ones
    (`oun`).
    """
    text = compare_key(value)
    result = []
    previous = None
    for index, char in enumerate(text):
        is_vowel = char in "aeiou" or (char == "y" and index > 0)
        mapped = "a" if is_vowel else char
        if mapped == previous:
            continue
        result.append(mapped)
        previous = mapped
    return "".join(result)


if __name__ == "__main__":
    samples = ["បង", "អូន", "យន់", "កុំ", "កុំ", "កំ", "តម្លៃ", "ស្រី", "ស្រុក", "ចម្រៀង",
               "ខ្ញុំ", "សាលា", "កក", "ជំរាបសួរ", "អរគុណ", "ទឹក", "ភាសា"]
    for sample in samples:
        roman = romanize(sample)
        print(f"{sample}\t{roman}\t{compare_key(roman)}\t{fuzzy_key(roman)}")
    print()
    for typed in ["bong", "oun", "kom", "domlai", "tomlai", "srey", "srok",
                  "chomrieng", "knhom", "sala", "chumreapsuor", "orkun", "tuk"]:
        print(f"{typed}\t{compare_key(typed)}\t{fuzzy_key(typed)}")
