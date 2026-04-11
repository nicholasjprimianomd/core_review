#!/usr/bin/env python3
"""For every question with missing/wrong correctChoice, find the raw PDF text
around its answer to show what format the extractor is failing on."""
from __future__ import annotations

import json, re, sys, io
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.path.insert(0, str(Path(__file__).resolve().parent))

import fitz
import extract_pdf_to_json as ext

REPO = Path(__file__).resolve().parents[1]

MATCHING_RE = re.compile(r"Matching answers:", re.IGNORECASE)

# All source paths (from reextract_all_books.py)
_TB = Path(r"C:\Users\nprim\Downloads\Textbooks-20260406T230727Z-3-001\Textbooks")
SOURCES: dict[str, Path] = {
    "breast-imaging": _TB / "Breast Imaging A Core Review.pdf",
    "cardiac": _TB / "Cardiac - A Core Review.pdf",
    "gastrointestinal": _TB / "Gastrointestinal - A Core Review.pdf",
    "genitourinary": _TB / "Genitourinary - A Core Review.pdf",
    "musculoskeletal-imaging": _TB / "Musculoskeletal Imaging - A Core Review- (2015).pdf",
    "neuroradiology": _TB / "Neuroradiology - A Core Review.pdf",
    "nuclear-medicine": _TB / "Nuclear Medicine - A Core Review.pdf",
    "pediatric-imaging": _TB / "Pediatric Imaging - A Core Review.pdf",
    "thoracic-imaging": _TB / "Thoracic Imaging - A Core Review.pdf",
    "ultrasound": _TB / "Ultrasound A Core Review.pdf",
    "vascular-and-interventional-radiology": _TB / "Vascular and Interventional Radiology - Unknown.pdf",
}

def find_answer_text_in_pdf(doc: fitz.Document, book_spec: ext.BookSpec, chapter_num: int, qnum_str: str) -> list[str]:
    """Search answer pages for the raw text around a given question number."""
    results = []
    chapter = None
    for ch in book_spec.chapters:
        if ch.number == chapter_num:
            chapter = ch
            break
    if chapter is None:
        return [f"  Chapter {chapter_num} not found in book spec"]

    # Search answer pages
    answer_start = chapter.answer_start_page or chapter.page
    for pg in range(answer_start, chapter.end_page + 1):
        page = doc[pg - 1]
        page_lines = ext.extract_page_lines(page)
        for i, li in enumerate(page_lines):
            text = li.text.strip()
            # Look for this question number at start of line
            if re.match(rf'^{re.escape(qnum_str)}\s', text) or re.match(rf'^{re.escape(qnum_str)}\.', text):
                context_start = max(0, i - 1)
                context_end = min(len(page_lines), i + 8)
                results.append(f"  pg{pg} line{i}:")
                for j in range(context_start, context_end):
                    lt = page_lines[j].text.strip()
                    marker = ">>>" if j == i else "   "
                    # Check what regex matches
                    flags = []
                    if ext.ANSWER_START_RE.match(lt): flags.append("ANS_START")
                    if ext.ANSWER_MATCHING_HEADER_RE.match(lt): flags.append("MATCH_HDR")
                    if ext.ANSWER_UNNUMBERED_RE.match(lt): flags.append("UNNUMBERED")
                    if ext.ANSWER_INLINE_MATCHING_RE.match(lt): flags.append("INLINE_MATCH")
                    if ext.CHOICE_START_RE.match(lt): flags.append("CHOICE")
                    flag_str = f" [{','.join(flags)}]" if flags else ""
                    results.append(f"  {marker} {lt[:120]}{flag_str}")
    return results


def find_choice_text_in_pdf(doc: fitz.Document, book_spec: ext.BookSpec, chapter_num: int, qnum_str: str) -> list[str]:
    """Search question pages for choice lines around a given question."""
    results = []
    chapter = None
    for ch in book_spec.chapters:
        if ch.number == chapter_num:
            chapter = ch
            break
    if chapter is None:
        return [f"  Chapter {chapter_num} not found"]

    end_pg = chapter.answer_start_page or chapter.end_page
    for pg in range(chapter.page, end_pg + 1):
        page = doc[pg - 1]
        page_lines = ext.extract_page_lines(page)
        for i, li in enumerate(page_lines):
            text = li.text.strip()
            if re.match(rf'^{re.escape(qnum_str)}\s', text) or re.match(rf'^{re.escape(qnum_str)}\.', text):
                context_end = min(len(page_lines), i + 20)
                results.append(f"  pg{pg} line{i} (question area):")
                for j in range(i, context_end):
                    lt = page_lines[j].text.strip()
                    flags = []
                    if ext.CHOICE_START_RE.match(lt): flags.append("CHOICE")
                    if ext.QUESTION_START_RE.match(lt) and j > i: flags.append("NEXT_Q")
                    flag_str = f" [{','.join(flags)}]" if flags else ""
                    results.append(f"    {lt[:120]}{flag_str}")
    return results


def main():
    qs = json.loads((REPO / "assets/data/questions.json").read_text(encoding="utf-8"))

    # Find all broken questions
    broken: list[dict] = []
    for q in qs:
        cc = (q.get("correctChoice") or "").strip()
        choices = q.get("choices") or {}
        expl = (q.get("explanation") or "").strip()
        is_matching = bool(MATCHING_RE.search(expl))

        issue = None
        if not cc and len(choices) >= 2 and not is_matching:
            issue = "MISSING_CC"
        elif cc and choices and cc not in choices and not is_matching:
            issue = "CC_NOT_IN_CHOICES"

        if issue:
            broken.append({**q, "_issue": issue})

    print(f"Total broken questions to diagnose: {len(broken)}")
    print()

    # Group by book
    by_book: dict[str, list[dict]] = {}
    for q in broken:
        by_book.setdefault(q["bookId"], []).append(q)

    for book_id in sorted(by_book.keys()):
        bqs = by_book[book_id]
        src = SOURCES.get(book_id)
        if src is None or not src.exists():
            print(f"=== {book_id}: source not found ({src}) ===")
            continue

        print(f"{'='*70}")
        print(f"BOOK: {book_id} ({len(bqs)} broken questions)")
        print(f"{'='*70}")

        doc = fitz.open(str(src))
        book_spec = ext.build_book_spec(src, order=1)

        for q in bqs:
            ch = q["chapterNumber"]
            qnum = q["questionNumber"]
            issue = q["_issue"]
            cc = (q.get("correctChoice") or "")
            choices = list((q.get("choices") or {}).keys())

            print(f"\n  --- {book_id} Ch{ch} Q{qnum} [{issue}] cc='{cc}' choices={choices} ---")

            # Find answer text
            answer_lines = find_answer_text_in_pdf(doc, book_spec, ch, qnum)
            for line in answer_lines:
                print(line)

            # For CC_NOT_IN_CHOICES, also show the question choices area
            if issue == "CC_NOT_IN_CHOICES":
                choice_lines = find_choice_text_in_pdf(doc, book_spec, ch, qnum)
                for line in choice_lines:
                    print(line)

        doc.close()
        print()


if __name__ == "__main__":
    main()
