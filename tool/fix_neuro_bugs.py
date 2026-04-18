"""Fix two correlated PDF-extraction bugs in the neuroradiology book:
  (1) Stem-continuation text leaked into the last answer choice of part A.
  (2) imageAssets within a stem group are rotated/swapped by one position.

Run from the repo root: `python tool/fix_neuro_bugs.py`.
"""

import json
from pathlib import Path

QUESTIONS_PATH = Path('assets/data/questions.json')

CHOICE_FIXES = {
    'neuroradiology-2-5a':  ('D', 'Toxoplasmosis'),
    'neuroradiology-2-15a': ('D', 'CT perfusion'),
    'neuroradiology-3-16a': ('D', 'Recommend an FDG-PET.'),
    'neuroradiology-3-21a': ('D', 'Metopic suture'),
    'neuroradiology-5-5a':  ('D', 'Basilar leptomeningeal enhancement without hydrocephalus'),
    'neuroradiology-10-2a': ('D', 'Osteophytosis'),
    'neuroradiology-11-3a': ('D', 'MRI without contrast'),
    'neuroradiology-16-4a': ('D', 'Frontal lobe'),
    'neuroradiology-16-8a': ('D', 'Pons'),
    'neuroradiology-16-9a': ('D', 'MRI of the pituitary with gadolinium'),
}

PROMPT_REPLACEMENTS = {
    'neuroradiology-3-21b': (
        'A 5-week-old girl presents with abnormal head shape. '
        'Key image from a CT head is shown below. '
        'Which of the following terms best describes the resulting skull morphology from the above shown premature synostosis?',
        'A 2-year-old girl presents with abnormal head shape and syndactyly. '
        'A volume-rendered 3D reconstruction from a CT head was generated, shown below. '
        'Which of the following terms best describes the resulting skull morphology from the above shown premature synostosis?',
    ),
}

IMAGE_ASSIGNMENTS = {
    'neuroradiology-1-4a':  ['assets/book_images/neuroradiology_page_021_img_1_1.png'],
    'neuroradiology-1-4b':  ['assets/book_images/neuroradiology_page_022_img_1_1.png'],

    'neuroradiology-2-5a':  ['assets/book_images/neuroradiology_page_091_img_1_1.png'],
    'neuroradiology-2-5b':  ['assets/book_images/neuroradiology_page_092_img_1_1.png'],

    'neuroradiology-2-15a': ['assets/book_images/neuroradiology_page_102_img_1_1.png'],
    'neuroradiology-2-15b': ['assets/book_images/neuroradiology_page_103_img_1_1.png'],

    'neuroradiology-3-2a':  ['assets/book_images/neuroradiology_page_136_img_1_1.png'],
    'neuroradiology-3-2b':  ['assets/book_images/neuroradiology_page_137_img_1_1.png'],

    'neuroradiology-3-16a': ['assets/book_images/neuroradiology_page_150_img_1_1.png'],
    'neuroradiology-3-16b': ['assets/book_images/neuroradiology_page_151_img_1_1.png'],

    'neuroradiology-3-19a': ['assets/book_images/neuroradiology_page_154_img_1_1.png'],
    'neuroradiology-3-19b': ['assets/book_images/neuroradiology_page_154_img_1_1.png'],
    'neuroradiology-3-19c': ['assets/book_images/neuroradiology_page_155_img_1_1.png'],

    'neuroradiology-3-21a': ['assets/book_images/neuroradiology_page_157_img_1_1.png'],
    'neuroradiology-3-21b': ['assets/book_images/neuroradiology_page_159_img_1_1.png'],

    'neuroradiology-5-5a':  ['assets/book_images/neuroradiology_page_247_img_1_1.png'],
    'neuroradiology-5-5b':  ['assets/book_images/neuroradiology_page_248_img_1_1.png'],

    'neuroradiology-6-15a': ['assets/book_images/neuroradiology_page_287_img_1_1.png'],
    'neuroradiology-6-15b': ['assets/book_images/neuroradiology_page_288_img_1_1.png'],

    # Ch. 7 Q5 (CCF, 45M with chemosis/proptosis): extractor put the AVM
    # figure from p.327 onto Q5c. The CCF case is fully depicted by the
    # three panels on p.326 (its own explanation references panels A-C).
    'neuroradiology-7-5a':  ['assets/book_images/neuroradiology_page_326_img_1_1.png'],
    'neuroradiology-7-5b':  ['assets/book_images/neuroradiology_page_326_img_1_1.png'],
    'neuroradiology-7-5c':  ['assets/book_images/neuroradiology_page_326_img_1_1.png'],

    # Ch. 7 Q6 (AVM with distended vein of Galen): the stem figure from
    # p.327 was stolen by Q5c above. Restore it to both parts of Q6.
    'neuroradiology-7-6a':  ['assets/book_images/neuroradiology_page_327_img_1_1.png'],
    'neuroradiology-7-6b':  ['assets/book_images/neuroradiology_page_327_img_1_1.png'],

    'neuroradiology-8-6a':  ['assets/book_images/neuroradiology_page_371_img_1_1.png'],
    'neuroradiology-8-6b':  ['assets/book_images/neuroradiology_page_372_img_1_1.png'],

    'neuroradiology-10-2a': ['assets/book_images/neuroradiology_page_440_img_1_1.png'],
    'neuroradiology-10-2b': ['assets/book_images/neuroradiology_page_441_img_1_1.png'],

    'neuroradiology-11-3a': ['assets/book_images/neuroradiology_page_486_img_1_1.png'],
    'neuroradiology-11-3b': ['assets/book_images/neuroradiology_page_487_img_1_1.png'],

    'neuroradiology-11-10a': ['assets/book_images/neuroradiology_page_495_img_1_1.png'],
    'neuroradiology-11-10b': ['assets/book_images/neuroradiology_page_495_img_1_1.png'],
    'neuroradiology-11-10c': ['assets/book_images/neuroradiology_page_496_img_1_1.png'],

    'neuroradiology-11-18a': ['assets/book_images/neuroradiology_page_505_img_1_1.png'],
    'neuroradiology-11-18b': ['assets/book_images/neuroradiology_page_506_img_1_1.png'],

    'neuroradiology-12-1a': ['assets/book_images/neuroradiology_page_543_img_1_1.png'],
    'neuroradiology-12-1b': ['assets/book_images/neuroradiology_page_544_img_1_1.png'],

    'neuroradiology-16-4a': ['assets/book_images/neuroradiology_page_684_img_1_1.png'],
    'neuroradiology-16-4b': ['assets/book_images/neuroradiology_page_685_img_1_1.png'],

    'neuroradiology-16-8a': ['assets/book_images/neuroradiology_page_689_img_1_1.png'],
    'neuroradiology-16-8b': ['assets/book_images/neuroradiology_page_690_img_1_1.png'],
    'neuroradiology-16-8c': ['assets/book_images/neuroradiology_page_691_img_1_1.png'],

    'neuroradiology-16-9a': ['assets/book_images/neuroradiology_page_692_img_1_1.png'],
    'neuroradiology-16-9b': ['assets/book_images/neuroradiology_page_693_img_1_1.png'],
}


def main():
    raw = QUESTIONS_PATH.read_text(encoding='utf-8')
    data = json.loads(raw)

    lookup = {q['id']: q for q in data}

    missing = [qid for qid in CHOICE_FIXES if qid not in lookup]
    missing += [qid for qid in IMAGE_ASSIGNMENTS if qid not in lookup]
    missing += [qid for qid in PROMPT_REPLACEMENTS if qid not in lookup]
    if missing:
        raise SystemExit(f'Missing ids: {missing}')

    changes = 0

    for qid, (letter, fixed) in CHOICE_FIXES.items():
        current = lookup[qid]['choices'][letter]
        if current != fixed:
            lookup[qid]['choices'][letter] = fixed
            changes += 1

    for qid, (old, new) in PROMPT_REPLACEMENTS.items():
        if lookup[qid]['prompt'] == old:
            lookup[qid]['prompt'] = new
            changes += 1
        elif lookup[qid]['prompt'] != new:
            raise SystemExit(f'Prompt for {qid} does not match expected old text')

    for qid, assets in IMAGE_ASSIGNMENTS.items():
        if lookup[qid]['imageAssets'] != assets:
            lookup[qid]['imageAssets'] = assets
            changes += 1

    QUESTIONS_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=True) + '\n',
        encoding='utf-8',
    )
    print(f'Applied {changes} changes.')


if __name__ == '__main__':
    main()
