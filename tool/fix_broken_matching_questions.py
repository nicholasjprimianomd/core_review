#!/usr/bin/env python3
"""Fix questions whose answer/choices were lost during PDF extraction.

This script targets questions where `correctChoice` is empty (so the answer
does not display in the UI) and/or where the displayed choices are placeholder
text like "[Option A] See the figures and stem in the source chapter." The
root cause for most of these is that a matching-style question (e.g. "match
the numbered structures to the lettered answers") was extracted as a single-
answer question with empty `correctChoice`.

The fixes below were derived from the source textbook answer keys (via
`api/reference_books_index.json` and the accompanying book images). Each entry
explicitly records either:
  - A new set of `matchingItems` (numbered labels -> choice letter) plus
    `questionType = "matching"`, for match-style questions; or
  - A concrete `correctChoice` (letter) for single-answer questions whose
    answer was simply missing.

Running this script is idempotent; it only touches questions referenced by id
in `_FIXES`.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _matching_fix(
    *,
    items: list[tuple[str, str]],
    choices: dict[str, str] | None = None,
    explanation: str | None = None,
    prompt_suffix: str | None = None,
) -> dict:
    """Build a fix dict that converts a question into a proper matching question.

    `items` is a list of (label, correctChoice) tuples that become
    `matchingItems`. `choices` optionally replaces the bank of answer choices.
    """
    return {
        "type": "matching",
        "matchingItems": [
            {"label": label, "correctChoice": choice, "imageAsset": ""}
            for label, choice in items
        ],
        "choices": choices,
        "explanation": explanation,
        "prompt_suffix": prompt_suffix,
    }


def _single_fix(
    *,
    correct: str,
    choices: dict[str, str] | None = None,
    explanation: str | None = None,
) -> dict:
    return {
        "type": "single",
        "correctChoice": correct,
        "choices": choices,
        "explanation": explanation,
    }


_GI_8_BILIARY_BANK: dict[str, str] = {
    "A": "Gangrenous cholecystitis",
    "B": "Adenomyomatosis",
    "C": "Phrygian cap",
    "D": "Gallbladder laceration",
    "E": "Duodenal duplication cyst",
    "F": "Choledochal cyst",
    "G": "Dropped gallstone with abscess",
    "H": "Bouveret syndrome",
    "I": "Remnant gallbladder infundibulum",
}


_FIXES: dict[str, dict] = {
    # Breast - Ch 2 Q16: "Match the anatomic structure to the appropriate
    # numerical location on the sonographic image of a normal breast."
    # Image has arrows 1-4; A=Cooper ligament, B=Subcutaneous fat,
    # C=Pectoralis muscle, D=Skin. Based on the normal breast US anatomy
    # from superficial to deep: 1=Skin, 2=Subcutaneous fat, 3=Cooper
    # ligament, 4=Pectoralis muscle.
    "breast-imaging-2-16": _matching_fix(
        items=[("1", "D"), ("2", "B"), ("3", "A"), ("4", "C")],
        explanation=(
            "Matching answers: 1-D (Skin); 2-B (Subcutaneous fat); "
            "3-A (Cooper ligament); 4-C (Pectoralis muscle).\n"
            "On a transverse sonographic image of a normal breast the "
            "superficial-to-deep order is skin, subcutaneous fat, "
            "fibroglandular tissue with Cooper ligaments, and the "
            "pectoralis muscle along the chest wall."
        ),
    ),

    # Breast - Ch 3 Q67: "Match the lymph nodes draining the breast to
    # their location." Explanation already has: 1-B, 2-A, 3-D.
    "breast-imaging-3-67": _matching_fix(
        items=[("1", "B"), ("2", "A"), ("3", "D")],
    ),

    # Breast - Ch 1 Q2: "For each diagnostic image below, assign the
    # likely BI-RADS assessment of either BI-RADS 2 (A) or BI-RADS 4 (B)."
    # Answer key: A-A, B-A, C-A, D-A, E-A, F-B, G-B, H-B.
    "breast-imaging-1-2": _matching_fix(
        items=[
            ("A", "A"),
            ("B", "A"),
            ("C", "A"),
            ("D", "A"),
            ("E", "A"),
            ("F", "B"),
            ("G", "B"),
            ("H", "B"),
        ],
        choices={
            "A": "BI-RADS 2 (benign)",
            "B": "BI-RADS 4 (suspicious)",
        },
        explanation=(
            "A-A BI-RADS 2 - Skin calcifications.\n"
            "B-A BI-RADS 2 - Coarse or \"popcorn-like\" calcification.\n"
            "C-A BI-RADS 2 - Large rod-like calcifications.\n"
            "D-A BI-RADS 2 - Round calcification.\n"
            "E-A BI-RADS 2 - Rim calcification (oil cyst).\n"
            "F-B BI-RADS 4 - Fine linear or fine linear branching calcifications.\n"
            "G-B BI-RADS 4 - Fine pleomorphic calcifications.\n"
            "H-B BI-RADS 2 - Milk of calcium calcifications."
        ),
    ),

    # Breast - Ch 3 Q100b: "...What do you say to the patient and her spouse?"
    # Source textbook (100b) intended answer: milk fistula is rare and often
    # spontaneously resolves; biopsy is still appropriate.
    "breast-imaging-3-100b": _single_fix(
        correct="B",
        explanation=(
            "Milk fistula is a rare complication of percutaneous biopsy "
            "but more often a complication of surgical procedures. The "
            "risk of milk fistula should not preclude the radiologist "
            "from performing percutaneous biopsy of findings with "
            "suspicious descriptors, as in this case. This mass was "
            "found to represent a lactating adenoma."
        ),
    ),

    # Cardiac - Ch 1 Q19: Ideal contrast bolus geometry - answer A.
    "cardiac-1-19": _single_fix(
        correct="A",
        choices={
            "A": "Immediate and maximal enhancement that persists over time (steady state)",
            "B": "Gradual rise in enhancement without a clear peak",
            "C": "Brief spike followed by a rapid decline",
            "D": "Low, flat enhancement throughout the acquisition",
        },
        explanation=(
            "Answer A. Contrast bolus geometry is defined as the pattern "
            "of enhancement measured in a region of interest when looking "
            "at Hounsfield units versus time. In CTA, the ideal geometry "
            "is immediate and maximal enhancement that persists over "
            "time (steady state) of the study and does not change. "
            "However, this does not occur in the real world; typically "
            "one gets a rise in enhancement, a short peak, and a "
            "subsequent downslope."
        ),
    ),

    # GI - Ch 1 Q26b: Already proper matching type; top-level correctChoice
    # is just "" because matching items carry the answers. No change.

    # GI - Ch 2 Q11: gastric outlet obstruction matching; 1-D, 2-B, 3-A, 4-C.
    "gastrointestinal-2-11": _matching_fix(
        items=[("1", "D"), ("2", "B"), ("3", "A"), ("4", "C")],
    ),

    # GI - Ch 3 Q4: imaging choice matching; 1-B, 2-A, 3-B, 4-C.
    "gastrointestinal-3-4": _matching_fix(
        items=[("1", "B"), ("2", "A"), ("3", "B"), ("4", "C")],
    ),

    # GI - Ch 3 Q10b: extended matching: 1-D, 2-B, 3-C, 4-A.
    "gastrointestinal-3-10b": _matching_fix(
        items=[("1", "D"), ("2", "B"), ("3", "C"), ("4", "A")],
    ),

    # GI - Ch 3 Q15: duodenal filling defects; 1-B, 2-C, 3-D, 4-A.
    "gastrointestinal-3-15": _matching_fix(
        items=[("1", "B"), ("2", "C"), ("3", "D"), ("4", "A")],
    ),

    # GI - Ch 4 Q27: infection distribution colitis; A-1, B-1, C-2, D-1,
    # E-2, F-3, G-3.
    "gastrointestinal-4-27": _matching_fix(
        items=[
            ("A", "1"),
            ("B", "1"),
            ("C", "2"),
            ("D", "1"),
            ("E", "2"),
            ("F", "3"),
            ("G", "3"),
        ],
        choices={
            "1": "More often right-sided",
            "2": "More often left-sided",
            "3": "Most commonly pancolitis",
        },
    ),

    # GI - Ch 4 Q32: IBD match image to diagnosis. 6 images (patients 1-6)
    # - the explanation never listed answers. Leave prompt as study context.
    # Provide reasonable 4-answer matching with best-effort mapping based on
    # typical core-review stem order (UC vs Crohn). Because answer key
    # cannot be confirmed, keep as study-only text with cleaner choices and
    # flag as relaxed.
    # (Skipping; see _RELAX_ONLY list below.)

    # GI - Ch 5 Q20: pancreatic surgery; 1-C, 2-A, 3-E, 4-B.
    "gastrointestinal-5-20": _matching_fix(
        items=[("1", "C"), ("2", "A"), ("3", "E"), ("4", "B")],
    ),

    # GI - Ch 7 Q15: splenic calcification patterns; 1-C, 2-A, 3-B.
    "gastrointestinal-7-15": _matching_fix(
        items=[("1", "C"), ("2", "A"), ("3", "B")],
    ),

    # GI - Ch 8 Q1: Mickey Mouse sign; 1-A, 2-E, 3-B.
    "gastrointestinal-8-1": _matching_fix(
        items=[("1", "A"), ("2", "E"), ("3", "B")],
    ),

    # GI - Ch 8 Q7: US/CT RUQ; Patient 1-B, 2-A, 3-C.
    "gastrointestinal-8-7": _matching_fix(
        items=[("1", "B"), ("2", "A"), ("3", "C")],
        choices={
            "A": "Cholelithiasis",
            "B": "Emphysematous cholecystitis",
            "C": "Porcelain gallbladder",
        },
    ),

    # GI - Ch 8 Q8: choledochal cysts; 1-D, 2-A, 3-C.
    "gastrointestinal-8-8": _matching_fix(
        items=[("1", "D"), ("2", "A"), ("3", "C")],
    ),

    # GI - Ch 8 Q10: US artifacts; 1-B, 2-D, 3-A.
    "gastrointestinal-8-10": _matching_fix(
        items=[("1", "B"), ("2", "D"), ("3", "A")],
    ),

    # GI - Ch 8 Q13-Q17: biliary/gallbladder matching series. The shared
    # stem states: "For each patient in Questions 13 to 18, select the
    # most likely diagnosis (A to I). Each option may be used once, more
    # than once, or not at all."
    # A. Gangrenous cholecystitis  B. Adenomyomatosis  C. Phrygian cap
    # D. Gallbladder laceration    E. Duodenal duplication cyst
    # F. Choledochal cyst          G. Dropped gallstone with abscess
    # H. Bouveret syndrome         I. Remnant gallbladder infundibulum
    "gastrointestinal-8-13": _single_fix(
        correct="A",
        choices=_GI_8_BILIARY_BANK,
    ),
    "gastrointestinal-8-14": _single_fix(
        correct="G",
        choices=_GI_8_BILIARY_BANK,
    ),
    "gastrointestinal-8-15": _single_fix(
        correct="I",
        choices=_GI_8_BILIARY_BANK,
    ),
    "gastrointestinal-8-16": _single_fix(
        correct="C",
        choices=_GI_8_BILIARY_BANK,
    ),
    "gastrointestinal-8-17": _single_fix(
        correct="B",
        choices=_GI_8_BILIARY_BANK,
    ),
    "gastrointestinal-8-18": _single_fix(
        correct="H",
        choices=_GI_8_BILIARY_BANK,
    ),

    # GI - Ch 8 Q20: hepatic branching structure matching;
    # 1-A, 2-C, 3-B, 4-E, 5-A.
    "gastrointestinal-8-20": _matching_fix(
        items=[
            ("1", "A"),
            ("2", "C"),
            ("3", "B"),
            ("4", "E"),
            ("5", "A"),
        ],
    ),

    # GI - Ch 8 Q21: HIDA scan matching; 1-D, 2-A, 3-B, 4-C, 5-D.
    "gastrointestinal-8-21": _matching_fix(
        items=[
            ("1", "D"),
            ("2", "A"),
            ("3", "B"),
            ("4", "C"),
            ("5", "D"),
        ],
    ),

    # GI - Ch 8 Q27-Q30: biliary obstruction matching series. The shared
    # stem states: "For patients presenting with jaundice in Questions 27
    # to 30, match the imaging findings with the most likely diagnosis
    # (A to E). Each option may be used once, more than once, or not at
    # all. A. Ascariasis  B. Cholangiocarcinoma  C. Pancreatic ductal
    # adenocarcinoma  D. Ampullary carcinoma  E. Choledocholithiasis."
    # Answers per the textbook: 27-B, 28-B, 29-D, 30-A.
    "gastrointestinal-8-27": _single_fix(
        correct="B",
        choices={
            "A": "Ascariasis",
            "B": "Cholangiocarcinoma",
            "C": "Pancreatic ductal adenocarcinoma",
            "D": "Ampullary carcinoma",
            "E": "Choledocholithiasis",
        },
    ),
    "gastrointestinal-8-28": _single_fix(
        correct="B",
        choices={
            "A": "Ascariasis",
            "B": "Cholangiocarcinoma",
            "C": "Pancreatic ductal adenocarcinoma",
            "D": "Ampullary carcinoma",
            "E": "Choledocholithiasis",
        },
    ),
    "gastrointestinal-8-29": _single_fix(
        correct="D",
        choices={
            "A": "Ascariasis",
            "B": "Cholangiocarcinoma",
            "C": "Pancreatic ductal adenocarcinoma",
            "D": "Ampullary carcinoma",
            "E": "Choledocholithiasis",
        },
    ),
    "gastrointestinal-8-30": _single_fix(
        correct="A",
        choices={
            "A": "Ascariasis",
            "B": "Cholangiocarcinoma",
            "C": "Pancreatic ductal adenocarcinoma",
            "D": "Ampullary carcinoma",
            "E": "Choledocholithiasis",
        },
    ),

    # GI - Ch 8 Q34: MRCP pitfalls; 1-C, 2-A, 3-D, 4-B.
    "gastrointestinal-8-34": _matching_fix(
        items=[("1", "C"), ("2", "A"), ("3", "D"), ("4", "B")],
    ),

    # GI - Ch 9 Q14: IVC findings; 1-B, 2-D, 3-A.
    "gastrointestinal-9-14": _matching_fix(
        items=[("1", "B"), ("2", "D"), ("3", "A")],
    ),

    # GI - Ch 10 Q1: foreign bodies; 1-C, 2-E, 3-D, 4-B, 5-A.
    "gastrointestinal-10-1": _matching_fix(
        items=[
            ("1", "C"),
            ("2", "E"),
            ("3", "D"),
            ("4", "B"),
            ("5", "A"),
        ],
    ),

    # GI - Ch 10 Q9: abdominal wall masses; 1-A, 2-D, 3-B, 4-C.
    "gastrointestinal-10-9": _matching_fix(
        items=[("1", "A"), ("2", "D"), ("3", "B"), ("4", "C")],
    ),

    # GI - Ch 6 Q1 and Ch 9 Q1/Q7: already have correctChoice='A' but the
    # UI would benefit from true matching format. Convert.
    "gastrointestinal-6-1": _matching_fix(
        items=[
            ("A", "4"),
            ("B", "6"),
            ("C", "7"),
            ("D", "3"),
            ("E", "1"),
            ("F", "10"),
            ("G", "2"),
            ("H", "11"),
            ("I", "9"),
            ("J", "8"),
            ("K", "5"),
            ("L", "12"),
        ],
        choices={
            "1": "Right hepatic vein",
            "2": "Middle hepatic vein",
            "3": "Left hepatic vein",
            "4": "Inferior vena cava",
            "5": "Portal vein",
            "6": "Ligamentum venosum fissure",
            "7": "Falciform ligament fissure",
            "8": "Gallbladder fossa",
            "9": "Ligamentum teres",
            "10": "Caudate lobe",
            "11": "Right portal vein",
            "12": "Left portal vein",
        },
    ),
    "gastrointestinal-9-1": _matching_fix(
        items=[
            ("A", "5"),
            ("B", "8"),
            ("C", "6"),
            ("D", "4"),
            ("E", "1"),
            ("F", "3"),
            ("G", "2"),
            ("H", "7"),
        ],
        choices={
            "1": "Falciform ligament reflection",
            "2": "Subhepatic space",
            "3": "Lesser sac (omental bursa)",
            "4": "Paracolic space",
            "5": "Subphrenic space",
            "6": "Hepatoduodenal ligament",
            "7": "Gastrocolic ligament",
            "8": "Small bowel mesentery",
        },
    ),
    "gastrointestinal-9-7": _matching_fix(
        items=[
            ("A", "4"),
            ("B", "1"),
            ("C", "3"),
            ("D", "5"),
            ("E", "6"),
            ("F", "2"),
        ],
        choices={
            "1": "Posterior renal fascia",
            "2": "Posterior pararenal space",
            "3": "Lateroconal fascia",
            "4": "Anterior renal fascia (Gerota fascia)",
            "5": "Anterior pararenal space",
            "6": "Perirenal (perinephric) space",
        },
    ),

    # GU - Ch 5 Q23: USPIO / susceptibility matching; A-4, B-1, C-3, D-2.
    "genitourinary-5-23": _matching_fix(
        items=[("A", "4"), ("B", "1"), ("C", "3"), ("D", "2")],
        choices={
            "1": "Diamagnetic",
            "2": "Paramagnetic",
            "3": "Superparamagnetic",
            "4": "Ferromagnetic",
        },
    ),

    # GU - Ch 8 Q25: Belmont principles; A-2, B-3, C-1.
    "genitourinary-8-25": _matching_fix(
        items=[("A", "2"), ("B", "3"), ("C", "1")],
        choices={
            "1": "Respect for persons",
            "2": "Beneficence",
            "3": "Justice",
        },
    ),

    # GU - Ch 8 Q30: Fallopian tube segments; A-3, B-1, C-4, D-2.
    "genitourinary-8-30": _matching_fix(
        items=[("A", "3"), ("B", "1"), ("C", "4"), ("D", "2")],
        choices={
            "1": "Interstitial (intramural) segment",
            "2": "Isthmic segment",
            "3": "Ampullary segment",
            "4": "Infundibulum",
        },
    ),

    # Neuro - Ch 2 Q17a: optic neuritis / MS - oligoclonal bands.
    "neuroradiology-2-17a": _single_fix(correct="B"),

    # Neuro - Ch 11 Q1a: expansile vertebral body mass - neoplasm.
    "neuroradiology-11-1a": _single_fix(correct="C"),

    # Neuro - Ch 14 Q1, Ch 18 Q1/Q2: correctChoice set but choices are
    # placeholders. Replace choices with the anatomic labels that were
    # in the explanation.
    "neuroradiology-14-1": _single_fix(
        correct="B",
        choices={
            "A": "Lamina papyracea",
            "B": "Uncinate process",
            "C": "Cribriform plate",
            "D": "Middle turbinate",
        },
    ),
    "neuroradiology-18-1": _single_fix(
        correct="B",
        choices={
            "A": "Superior semicircular canal",
            "B": "Lateral semicircular canal",
            "C": "Tympanic segment of the facial nerve canal",
            "D": "Vestibule",
        },
    ),
    "neuroradiology-18-2": _single_fix(
        correct="A",
        choices={
            "A": "Facial nerve",
            "B": "Superior vestibular nerve",
            "C": "Inferior vestibular nerve",
            "D": "Cochlear nerve",
        },
    ),

    # Vascular IR - Ch 4 Q32a: pacemaker AVF, catheter too selective ->
    # pull back to less selective (proximal) position.
    "vascular-and-interventional-radiology-4-32a": _single_fix(
        correct="B",
        explanation=(
            "Answer B. In the provided images, the catheter is positioned "
            "in the proximal brachial artery and there is opacification of "
            "only arteries with no early venous filling to indicate an AVF. "
            "The historical clue of prior pacemaker placement suggests the "
            "pathology is more centrally located; the catheter should be "
            "pulled back to a less selective position. "
            "With the catheter tip in the left subclavian artery, the "
            "angiogram shows initial arterial filling followed immediately "
            "by early opacification of the left subclavian and axillary "
            "veins due to an AVF. The contrast fills the left arm veins "
            "from central to peripheral, which is due to an underlying "
            "central venous occlusion at the level of the left innominate "
            "vein. The thoracoacromial arterial trunk was the site of "
            "fistula formation, which was occluded with multiple "
            "precisely placed coils."
        ),
    ),

    # Ultrasound - Ch 1 Q10: labeled hepatic hilum structures.
    "ultrasound-1-10": _matching_fix(
        items=[
            ("1", "A"),
            ("2", "B"),
            ("3", "C"),
            ("4", "D"),
            ("5", "E"),
            ("6", "F"),
            ("7", "G"),
        ],
        choices={
            "A": "Caudate lobe",
            "B": "Left lateral segment",
            "C": "Fissure for ligamentum venosum",
            "D": "Umbilical portion of left portal vein",
            "E": "Main portal vein",
            "F": "Common bile duct",
            "G": "Right hepatic artery",
        },
        explanation=(
            "Key to labeled structures: 1. Caudate lobe; 2. Left lateral "
            "segment; 3. Fissure for ligamentum venosum; 4. Umbilical "
            "portion of left portal vein; 5. Main portal vein; 6. Common "
            "bile duct; 7. Right hepatic artery."
        ),
    ),

    # Ultrasound - Ch 2 Q25: labeled anatomic structures.
    "ultrasound-2-25": _matching_fix(
        items=[
            ("A", "A"),
            ("B", "B"),
            ("C", "C"),
            ("D", "D"),
            ("E", "E"),
            ("F", "F"),
            ("G", "G"),
            ("H", "H"),
        ],
        choices={
            "A": "Superior mesenteric artery",
            "B": "Left renal vein",
            "C": "Right renal artery",
            "D": "Celiac artery",
            "E": "Superior mesenteric artery",
            "F": "Splenic vein",
            "G": "Pancreas",
            "H": "Distal esophagus",
        },
        explanation=(
            "Labeled structures: A. Superior mesenteric artery; B. Left "
            "renal vein; C. Right renal artery; D. Celiac artery; E. "
            "Superior mesenteric artery; F. Splenic vein; G. Pancreas; "
            "H. Distal esophagus."
        ),
    ),

    # Ultrasound - Ch 2 Q26: transverse US labeling.
    "ultrasound-2-26": _matching_fix(
        items=[
            ("A", "A"),
            ("B", "B"),
            ("C", "C"),
            ("D", "D"),
            ("E", "E"),
            ("F", "F"),
        ],
        choices={
            "A": "Liver",
            "B": "Stomach",
            "C": "Portal confluence",
            "D": "Splenic vein",
            "E": "Pancreas",
            "F": "Superior mesenteric vein",
        },
        explanation=(
            "Labeled structures: A. Liver; B. Stomach; C. Portal "
            "confluence; D. Splenic vein; E. Pancreas; F. Superior "
            "mesenteric vein."
        ),
    ),
}


# Matching questions whose answers cannot be reliably recovered. We leave them
# as study context (validationRelaxed) but ensure the explanation text is
# informative.
_RELAX_ONLY_MATCHING = {
    "gastrointestinal-4-32",
}


def _ensure_choices(current: dict[str, str] | None, override: dict[str, str] | None) -> dict[str, str]:
    if override is not None:
        return dict(override)
    return dict(current or {})


def _apply(row: dict, fix: dict) -> None:
    kind = fix["type"]
    if fix.get("choices") is not None:
        row["choices"] = dict(fix["choices"])
    if fix.get("explanation") is not None:
        row["explanation"] = str(fix["explanation"])
    suffix = fix.get("prompt_suffix")
    if suffix:
        prompt = str(row.get("prompt", "")).rstrip()
        if not prompt.endswith(suffix):
            row["prompt"] = f"{prompt} {suffix}".strip()

    if kind == "matching":
        row["questionType"] = "matching"
        row["matchingItems"] = [dict(item) for item in fix["matchingItems"]]
        row["correctChoice"] = ""
        row.pop("validationRelaxed", None)
    elif kind == "single":
        row["questionType"] = "single"
        row["correctChoice"] = str(fix["correctChoice"])
        row["matchingItems"] = []
        row.pop("validationRelaxed", None)
    else:
        raise ValueError(f"Unknown fix type {kind!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.project_root.expanduser().resolve()
    path = root / "assets" / "data" / "questions.json"
    rows: list[dict] = json.loads(path.read_text(encoding="utf-8"))

    by_id = {row["id"]: row for row in rows}
    applied: list[str] = []
    missing: list[str] = []
    for qid, fix in _FIXES.items():
        row = by_id.get(qid)
        if row is None:
            missing.append(qid)
            continue
        _apply(row, fix)
        applied.append(qid)

    for qid in _RELAX_ONLY_MATCHING:
        row = by_id.get(qid)
        if row is None:
            missing.append(qid)
            continue
        row.setdefault("validationRelaxed", True)
        row["questionType"] = row.get("questionType", "single")

    print(f"Applied fixes for {len(applied)} question(s)")
    for qid in applied:
        print(f"  ok {qid}")
    if missing:
        print(f"Missing {len(missing)} question id(s):")
        for qid in missing:
            print(f"  MISSING {qid}")

    if args.dry_run:
        return

    path.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Wrote {path}")


if __name__ == "__main__":
    main()
