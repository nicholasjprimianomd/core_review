"""Fix leaked answer-choice labels in Gastrointestinal Ch. 6 (Liver).

The PDF extractor mixed up the label lists at two section boundaries:

  * Q36-Q40 ("which primary tumor caused these liver metastases?") got
    stamped with the generic 6-option tumor list used by Q3-Q15
    (hemangioma / HCA / FNH / HCC / cholangio / abscess) instead of the
    primary-tumor list that is still visible on Q35.

  * Q47-Q50 ("which nodule pattern / cirrhosis finding is shown?") got
    the same generic 6-option tumor list instead of the nodule/infarct
    list that is still visible on Q46.

In each case the `correctChoice` letter is already the right answer
letter; only the labels are wrong. Pull the label dict from the
predecessor that is carrying them by mistake and apply it to the
"shifted" block.

Run: `python tool/fix_gi_liver_choice_leaks.py`
"""

from __future__ import annotations

import json
from pathlib import Path

QUESTIONS_PATH = Path("assets/data/questions.json")

# Labels we expect to see on the generic (wrong) 6-option set so we
# only replace questions that actually have that leaked set, never
# touch ones already carrying correct content.
_GENERIC_TUMOR_LIST = {
    "A": "Cavernous hemangioma",
    "B": "Hepatocellular adenoma",
    "C": "Focal nodular hyperplasia",
    "D": "Hepatocellular carcinoma",
    "E": "Cholangiocarcinoma",
    "F": "Abscess",
}

_PRIMARY_TUMOR_LIST = {
    "A": "Pancreatic ductal carcinoma",
    "B": "Neuroendocrine tumor",
    "C": "Non-small cell lung carcinoma",
    "D": "Breast carcinoma",
    "E": "Lymphoid tumor",
    "F": "Mucinous colorectal carcinoma",
}

_NODULE_LIST = {
    "A": "Siderotic nodule",
    "B": "Regenerative nodule, nonsiderotic",
    "C": "Nodular steatosis",
    "D": "Infarct",
}

_CYSTIC_LIVER_LIST = {
    "A": "Von Meyenburg complex",
    "B": "Pyogenic abscess",
    "C": "Biliary cystadenoma/cystadenocarcinoma",
    "D": "Peritoneal carcinomatosis",
    "E": "Polycystic liver disease in autosomal-dominant polycystic kidney disease",
    "F": "Subcapsular hematoma",
}

# qid -> (expected currently-leaked dict, corrected dict, expected
# correctChoice letter to preserve as a sanity check).
TARGETED_FIXES: dict[str, tuple[dict[str, str], dict[str, str], str]] = {
    "gastrointestinal-6-36": (_GENERIC_TUMOR_LIST, _PRIMARY_TUMOR_LIST, "F"),
    "gastrointestinal-6-37": (_GENERIC_TUMOR_LIST, _PRIMARY_TUMOR_LIST, "B"),
    "gastrointestinal-6-38": (_GENERIC_TUMOR_LIST, _PRIMARY_TUMOR_LIST, "E"),
    "gastrointestinal-6-39": (_GENERIC_TUMOR_LIST, _PRIMARY_TUMOR_LIST, "D"),
    "gastrointestinal-6-40": (_GENERIC_TUMOR_LIST, _PRIMARY_TUMOR_LIST, "C"),
    "gastrointestinal-6-47": (_GENERIC_TUMOR_LIST, _NODULE_LIST, "C"),
    "gastrointestinal-6-48": (_GENERIC_TUMOR_LIST, _NODULE_LIST, "B"),
    "gastrointestinal-6-49": (_GENERIC_TUMOR_LIST, _NODULE_LIST, "D"),
    "gastrointestinal-6-50": (_GENERIC_TUMOR_LIST, _NODULE_LIST, "A"),
    # Q11 still holds the cystic-lesion differential on its own options
    # slot (with the BCS explanation). Q12-Q15's explanations each
    # correspond to an entry in that cystic list, but their options
    # were stamped with the generic tumor set instead. Fix Q12-Q15.
    "gastrointestinal-6-12": (_GENERIC_TUMOR_LIST, _CYSTIC_LIVER_LIST, "C"),
    "gastrointestinal-6-13": (_GENERIC_TUMOR_LIST, _CYSTIC_LIVER_LIST, "E"),
    "gastrointestinal-6-14": (_GENERIC_TUMOR_LIST, _CYSTIC_LIVER_LIST, "B"),
    "gastrointestinal-6-15": (_GENERIC_TUMOR_LIST, _CYSTIC_LIVER_LIST, "A"),
}


def main() -> None:
    data = json.loads(QUESTIONS_PATH.read_text(encoding="utf-8"))
    lookup = {q["id"]: q for q in data}

    missing = [qid for qid in TARGETED_FIXES if qid not in lookup]
    if missing:
        raise SystemExit(f"Missing ids: {missing}")

    changes = 0
    skipped: list[tuple[str, str]] = []
    for qid, (expected_current, replacement, expected_letter) in TARGETED_FIXES.items():
        q = lookup[qid]
        if q.get("correctChoice") != expected_letter:
            skipped.append((qid, f"correctChoice is {q.get('correctChoice')} not {expected_letter}"))
            continue
        if q.get("choices") != expected_current:
            if q.get("choices") == replacement:
                continue
            skipped.append((qid, "choices already diverge from the expected leaked set"))
            continue
        q["choices"] = dict(replacement)
        changes += 1

    QUESTIONS_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"Applied {changes} choice-label fixes.")
    for qid, reason in skipped:
        print(f"  skipped {qid}: {reason}")


if __name__ == "__main__":
    main()
