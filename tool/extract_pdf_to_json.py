from __future__ import annotations

import argparse
import json
import posixpath
import re
import shutil
import zipfile
from collections import defaultdict
from dataclasses import dataclass, field
from html import unescape
from pathlib import Path

import fitz


QUESTION_START_RE = re.compile(r"^(?P<number>\d+[a-z]?)\s*\.?\s+(?P<text>.+)$")
QUESTION_NUMBER_ONLY_RE = re.compile(r"^(?P<number>\d+[a-z]?)\s*\.?$")
ANSWER_START_RE = re.compile(
    r"^(?P<number>\d{1,2}[a-z]?)\s*\.?\s+Answer(?::|\s+)\s*(?P<choice>[A-H])\s*\.\s*(?P<text>.*)$",
    re.IGNORECASE,
)
# Many Core Review chapters use "Answer A. ..." without a leading question number; pair with chapter order.
ANSWER_UNNUMBERED_RE = re.compile(
    r"^Answer\s+(?P<choice>[A-H])\s*\.\s*(?P<text>.*)$",
    re.IGNORECASE,
)
# Citation page numbers can glue to the next line (e.g. "344 Answer D.") — treat like unnumbered.
ANSWER_PAGE_REF_PREFIX_RE = re.compile(
    r"^(?P<pref>\d{3,})\s+Answer\s+(?P<choice>[A-H])\s*\.\s*(?P<text>.*)$",
    re.IGNORECASE,
)
CHOICE_START_RE = re.compile(r"^(?P<choice>[A-H])\.\s*(?P<text>.*)$")
REFERENCE_START_RE = re.compile(r"^References?:\s*(?P<text>.*)$", re.IGNORECASE)
CHAPTER_TOC_RE = re.compile(r"^(?P<number>\d+)\s+(?P<title>.+)$")
GENERIC_CHAPTER_TOC_RE = re.compile(r"^Chapter\s+(?P<number>\d+)$", re.IGNORECASE)
SECTION_NUMBER_RE = re.compile(r"^Section\s+(?P<number>\d+):\s*(?P<title>.+)$", re.IGNORECASE)
IMAGE_REFERENCE_RE = re.compile(
    r"\[image\]"
    r"|shown\s+(?:above|below|here)\b"
    r"|shown\s+is\b"
    r"|images?.*shown\b"
    r"|based on\s+(?:the|these|following|diagnostic|ultrasound|mammogram|mr|mri|ct).*images?"
    r"|the following images?\b"
    r"|images?\s+available\b"
    r"|pictured here\b",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class TocEntry:
    level: int
    title: str
    page: int


@dataclass(frozen=True)
class TopicSpec:
    id: str
    title: str
    order: int
    page: int


@dataclass(frozen=True)
class SectionSpec:
    id: str
    title: str
    number: int
    page: int


@dataclass(frozen=True)
class ChapterSpec:
    id: str
    number: int
    title: str
    page: int
    end_page: int
    answer_start_page: int | None
    topic_id: str | None
    topic_title: str | None
    sections: tuple[SectionSpec, ...]


@dataclass(frozen=True)
class BookSpec:
    id: str
    title: str
    source_file_name: str
    order: int
    topics: tuple[TopicSpec, ...]
    chapters: tuple[ChapterSpec, ...]


@dataclass
class LineInfo:
    y: float
    text: str


@dataclass
class QuestionDraft:
    id: str
    book_id: str
    book_title: str
    chapter: ChapterSpec
    question_number: str
    order: int
    stem_group: str
    start_page: int
    topic_id: str | None = None
    topic_title: str | None = None
    section: SectionSpec | None = None
    raw_lines: list[str] = field(default_factory=list)
    prompt: str = ""
    choices: dict[str, str] = field(default_factory=dict)
    correct_choice: str = ""
    explanation: str = ""
    references: list[str] = field(default_factory=list)
    image_assets: list[str] = field(default_factory=list)
    explanation_image_assets: list[str] = field(default_factory=list)


@dataclass
class AnswerDraft:
    question_id: str
    correct_choice: str
    lines: list[str] = field(default_factory=list)


def slugify(value: str) -> str:
    return re.sub(r"-{2,}", "-", re.sub(r"[^a-z0-9]+", "-", value.lower())).strip("-")


def clean_text(value: str) -> str:
    value = value.replace("\u2013", "-").replace("\u2014", "-").replace("\u2019", "'")
    value = value.replace("\xa0", " ").replace("\t", " ")
    value = value.replace("’", "'").replace("–", "-")
    return re.sub(r"\s+", " ", value).strip()


def collapse_lines(lines: list[str]) -> str:
    return clean_text(" ".join(line for line in lines if line.strip()))


def unique_preserving_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []

    for value in values:
        if value in seen:
            continue
        seen.add(value)
        ordered.append(value)

    return ordered


# Drop decorative PDF icons; real figures are almost always larger.
_MIN_FIGURE_SIDE_PT = 90.0
_MIN_FIGURE_AREA_PT2 = _MIN_FIGURE_SIDE_PT * _MIN_FIGURE_SIDE_PT


def question_image_anchor_index_and_owner(
    anchors: list[tuple[float, str]],
    rect: fitz.Rect,
    carry_question_id: str | None,
) -> tuple[int | None, str | None]:
    """
    Map an image rect to a question id and the anchor row index for that question
    (used to clip figures to the vertical band between adjacent questions).
    """
    applicable_index: int | None = None
    applicable_owner: str | None = None
    for i, (anchor_y, anchor_question_id) in enumerate(anchors):
        if anchor_y <= rect.y0 + 2:
            applicable_index = i
            applicable_owner = anchor_question_id
        else:
            break
    if applicable_owner is not None:
        return applicable_index, applicable_owner
    if anchors:
        first_anchor_y, first_anchor_id = anchors[0]
        if rect.y0 + 2 < first_anchor_y:
            return 0, first_anchor_id
        return None, carry_question_id
    return None, carry_question_id


def rect_in_question_vertical_band(
    rect: fitz.Rect,
    anchors: list[tuple[float, str]],
    anchor_index: int,
    page_height: float,
    *,
    y_slack_pt: float = 8.0,
) -> bool:
    """True if the figure's top lies between the previous and next question anchors."""
    y_lo = anchors[anchor_index - 1][0] if anchor_index > 0 else 0.0
    y_hi = (
        anchors[anchor_index + 1][0]
        if anchor_index + 1 < len(anchors)
        else page_height
    )
    return (rect.y0 >= y_lo - y_slack_pt) and (rect.y0 < y_hi)


def normalized_header_key(value: str) -> str:
    return re.sub(r"[^A-Z]", "", value.upper())


def stem_group(question_number: str) -> str:
    match = re.match(r"(\d+)", question_number)
    return match.group(1) if match else question_number


def split_question_number(question_number: str) -> tuple[int, str]:
    match = re.match(r"(?P<number>\d+)(?P<suffix>[a-z]?)", question_number.lower())
    if match is None:
        return 0, ""
    return int(match.group("number")), match.group("suffix")


def is_plausible_next_question(
    candidate_question_number: str,
    previous_question_number: str | None,
) -> bool:
    if previous_question_number is None:
        return True

    previous_number, previous_suffix = split_question_number(previous_question_number)
    candidate_number, candidate_suffix = split_question_number(candidate_question_number)

    if candidate_number < previous_number:
        return False

    if candidate_number > previous_number + 1:
        return False

    if candidate_number == previous_number:
        if not previous_suffix and candidate_suffix:
            return True
        if previous_suffix and candidate_suffix and candidate_suffix > previous_suffix:
            return True
        return False

    return True


def prompt_mentions_figure(prompt: str) -> bool:
    return bool(
        IMAGE_REFERENCE_RE.search(prompt)
        or re.search(
            r"\b(below|provided|arrow|same patient|shown above|shown below)\b",
            prompt,
            re.IGNORECASE,
        )
    )


def format_topic_title(title: str) -> str:
    cleaned = clean_text(title)
    section_match = re.match(r"^SECTION\s+\d+:\s*(?P<title>.+)$", cleaned, re.IGNORECASE)
    if section_match:
        return clean_text(section_match.group("title"))
    return cleaned.title() if cleaned.isupper() else cleaned


def format_section_title(title: str, fallback_number: int) -> tuple[int, str]:
    cleaned = clean_text(title)
    section_match = SECTION_NUMBER_RE.match(cleaned)
    if section_match:
        return int(section_match.group("number")), clean_text(section_match.group("title"))
    return fallback_number, cleaned


def format_book_title(pdf_path: Path) -> str:
    title = pdf_path.stem
    title = re.sub(r"\s*-\s*A Core Review.*$", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\s+A Core Review.*$", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\s*-\s*Unknown$", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\s*-\s*\(\d{4}\)$", "", title)
    return clean_text(title).strip(" -")


def is_ignored_toc_title(title: str) -> bool:
    normalized = clean_text(title).lower()
    return normalized.startswith("oebps-") or normalized in {
        "cover",
        "half title",
        "title",
        "title page",
        "copyright",
        "dedication",
        "contributors",
        "series foreword",
        "foreword",
        "preface",
        "acknowledgments",
        "acknowledgements",
        "contents",
        "content",
        "table of contents",
        "answers",
        "answer",
        "blank page",
        "index",
    }


def resolve_chapter_number_and_title(
    chapter_entry: TocEntry,
    doc: fitz.Document,
    fallback_number: int,
) -> tuple[int, str]:
    chapter_match = CHAPTER_TOC_RE.match(chapter_entry.title)
    if chapter_match is not None:
        return (
            int(chapter_match.group("number")),
            clean_text(chapter_match.group("title")),
        )

    generic_chapter_match = GENERIC_CHAPTER_TOC_RE.match(chapter_entry.title)
    if generic_chapter_match is None:
        return fallback_number, clean_text(chapter_entry.title)

    chapter_number = int(generic_chapter_match.group("number"))
    page_lines = extract_page_lines(doc[chapter_entry.page - 1])
    title_lines: list[str] = []

    for line in page_lines[:12]:
        text = line.text
        if text.upper() == "QUESTIONS":
            break
        if text == str(chapter_number):
            continue
        if text.startswith("P."):
            continue
        title_lines.append(text)

    title = collapse_lines(title_lines)
    return chapter_number, title or chapter_entry.title


def default_source_paths() -> list[Path]:
    downloads = Path.home() / "Downloads"
    return [
        downloads / "Thoracic Imaging - A Core Review.pdf",
        downloads / "OneDrive_1_3-13-2026",
    ]


def discover_pdf_paths(input_paths: list[Path]) -> list[Path]:
    discovered: list[Path] = []

    for input_path in input_paths:
        resolved = input_path.expanduser().resolve()
        if not resolved.exists():
            continue

        if resolved.is_file() and resolved.suffix.lower() in {".pdf", ".epub"}:
            discovered.append(resolved)
            continue

        if resolved.is_dir():
            discovered.extend(sorted(resolved.glob("*.pdf")))
            discovered.extend(sorted(resolved.glob("*.epub")))

    unique_paths: list[Path] = []
    seen: set[Path] = set()
    for path in discovered:
        if path in seen:
            continue
        seen.add(path)
        unique_paths.append(path)

    return unique_paths


def extract_page_lines(page: fitz.Page) -> list[LineInfo]:
    page_dict = page.get_text("dict")
    page_lines: list[LineInfo] = []

    for block in page_dict["blocks"]:
        if block.get("type") != 0:
            continue

        for line in block.get("lines", []):
            text = clean_text(" ".join(span.get("text", "") for span in line.get("spans", [])))
            if text:
                page_lines.append(LineInfo(y=float(line["bbox"][1]), text=text))

    page_lines.sort(key=lambda entry: (entry.y, entry.text))
    page_lines = preprocess_page_lines(page_lines)
    page_lines = expand_fused_choice_lines(page_lines)
    page_lines = merge_dangling_reference_answers(page_lines)
    return expand_glued_reference_answers(page_lines)


def expand_fused_choice_lines(page_lines: list[LineInfo]) -> list[LineInfo]:
    """Split lines like 'E. cystic F. mature G. x H. y' into separate choice lines (Core Review pancreas, etc.)."""
    expanded: list[LineInfo] = []
    # Two or more single-letter choice markers (A.–H.) on one physical line
    multi_choice = re.compile(r"(?:^|\s)([A-H])\.\s", re.IGNORECASE)

    for li in page_lines:
        text = li.text.strip()
        if not text:
            expanded.append(li)
            continue
        markers = list(multi_choice.finditer(text))
        if len(markers) < 2:
            expanded.append(li)
            continue
        segments = [
            s.strip()
            for s in re.split(r"(?<=\S)\s+(?=[A-H]\.\s)", text, flags=re.IGNORECASE)
            if s.strip()
        ]
        if len(segments) < 2:
            expanded.append(li)
            continue
        for seg in segments:
            expanded.append(LineInfo(y=li.y, text=seg))
    return expanded


def merge_dangling_reference_answers(page_lines: list[LineInfo]) -> list[LineInfo]:
    """Join lines like '...59-' + '70 Answer A.' into one line before splitting."""
    if len(page_lines) < 2:
        return page_lines
    merged: list[LineInfo] = [page_lines[0]]
    for i in range(1, len(page_lines)):
        prev = merged[-1]
        cur = page_lines[i]
        if prev.text.rstrip().endswith("-") and re.match(
            r"^\d+\s+Answer\s+[A-H]\.",
            cur.text.strip(),
            re.IGNORECASE,
        ):
            merged[-1] = LineInfo(y=prev.y, text=prev.text + cur.text)
        else:
            merged.append(cur)
    return merged


def expand_glued_reference_answers(page_lines: list[LineInfo]) -> list[LineInfo]:
    """Split citation tails like '...59-70 Answer A.' into two lines so answers parse correctly."""
    expanded: list[LineInfo] = []
    glue_pat = re.compile(r"(-\d+)\s+(Answer\s+[A-H]\.\s*)", re.IGNORECASE)
    for li in page_lines:
        m = glue_pat.search(li.text)
        if m is not None and m.start(2) > 0:
            prefix = li.text[: m.start(2)].rstrip()
            suffix = li.text[m.start(2) :].lstrip()
            expanded.append(LineInfo(y=li.y, text=prefix))
            expanded.append(LineInfo(y=li.y, text=suffix))
        else:
            expanded.append(li)
    return expanded


def preprocess_page_lines(page_lines: list[LineInfo]) -> list[LineInfo]:
    normalized_lines: list[LineInfo] = []
    index = 0

    while index < len(page_lines):
        current_line = page_lines[index]
        if index + 1 < len(page_lines):
            next_line = page_lines[index + 1]
            current_number_match = QUESTION_NUMBER_ONLY_RE.match(current_line.text)
            if (
                current_number_match is not None
                and next_line.text.upper().startswith("ANSWER ")
            ):
                normalized_lines.append(
                    LineInfo(
                        y=current_line.y,
                        text=f"{current_number_match.group('number')} {next_line.text}",
                    )
                )
                index += 2
                continue
            next_number_match = QUESTION_NUMBER_ONLY_RE.match(next_line.text)
            if (
                next_number_match is not None
                and QUESTION_START_RE.match(current_line.text) is None
                and QUESTION_NUMBER_ONLY_RE.match(current_line.text) is None
                and CHOICE_START_RE.match(current_line.text) is None
                and normalized_header_key(current_line.text)
                not in {"QUESTIONS", "ANSWERS", "ANSWERSANDEXPLANATIONS", "ANSWER"}
                and abs(next_line.y - current_line.y) <= 4
            ):
                normalized_lines.append(
                    LineInfo(
                        y=current_line.y,
                        text=f"{next_number_match.group('number')} {current_line.text}",
                    )
                )
                index += 2
                continue

        normalized_lines.append(current_line)
        index += 1

    return normalized_lines


def parse_question_content(raw_lines: list[str]) -> tuple[str, dict[str, str]]:
    prompt_lines: list[str] = []
    choices: dict[str, str] = {}
    current_choice: str | None = None

    for line in raw_lines:
        text = clean_text(line)
        if not text:
            continue

        choice_match = CHOICE_START_RE.match(text)
        if choice_match:
            current_choice = choice_match.group("choice")
            choices[current_choice] = clean_text(choice_match.group("text"))
            continue

        if current_choice is None:
            prompt_lines.append(text)
        else:
            choices[current_choice] = clean_text(f"{choices[current_choice]} {text}")

    return collapse_lines(prompt_lines), choices


def parse_answer_content(raw_lines: list[str]) -> tuple[str, list[str]]:
    explanation_lines: list[str] = []
    reference_lines: list[str] = []
    collecting_references = False

    for line in raw_lines:
        text = clean_text(line)
        if not text:
            continue

        reference_match = REFERENCE_START_RE.match(text)
        if reference_match:
            collecting_references = True
            remainder = clean_text(reference_match.group("text"))
            if remainder:
                reference_lines.append(remainder)
            continue

        if collecting_references:
            reference_lines.append(text)
        else:
            explanation_lines.append(text)

    references = [collapse_lines(reference_lines)] if reference_lines else []
    return collapse_lines(explanation_lines), references


def build_book_spec(pdf_path: Path, order: int) -> BookSpec:
    doc = fitz.open(pdf_path)
    toc_entries = [
        TocEntry(level=level, title=clean_text(title), page=page)
        for level, title, page in doc.get_toc(simple=True)
        if page > 0
    ]

    index_page = next(
        (entry.page for entry in toc_entries if entry.title.lower() == "index"),
        doc.page_count + 1,
    )
    chapter_entries = [
        entry
        for entry in toc_entries
        if CHAPTER_TOC_RE.match(entry.title) or GENERIC_CHAPTER_TOC_RE.match(entry.title)
    ]
    if not chapter_entries:
        chapter_entries = [
            entry
            for entry in toc_entries
            if not is_ignored_toc_title(entry.title) and entry.page < index_page
        ]
    if not chapter_entries:
        raise RuntimeError(f"Unable to find chapter bookmarks in {pdf_path}")

    first_chapter_page = min(entry.page for entry in chapter_entries)
    relevant_entries = [
        entry
        for entry in toc_entries
        if first_chapter_page <= entry.page < index_page
    ]

    topics_by_id: dict[str, TopicSpec] = {}
    chapters: list[ChapterSpec] = []
    book_id = slugify(format_book_title(pdf_path))

    for index, chapter_entry in enumerate(chapter_entries):
        chapter_number, chapter_title = resolve_chapter_number_and_title(
            chapter_entry,
            doc,
            fallback_number=index + 1,
        )
        next_chapter_page = (
            chapter_entries[index + 1].page - 1
            if index + 1 < len(chapter_entries)
            else index_page - 1
        )
        chapter_level = chapter_entry.level

        preceding_topic = None
        for entry in relevant_entries:
            if entry.page > chapter_entry.page:
                break
            if entry.title == chapter_entry.title or CHAPTER_TOC_RE.match(entry.title):
                continue
            if entry.level < chapter_level:
                preceding_topic = entry

        topic_id: str | None = None
        topic_title: str | None = None
        if preceding_topic is not None:
            topic_title = format_topic_title(preceding_topic.title)
            topic_id = f"{book_id}-topic-{slugify(topic_title)}"
            topics_by_id.setdefault(
                topic_id,
                TopicSpec(
                    id=topic_id,
                    title=topic_title,
                    order=len(topics_by_id) + 1,
                    page=preceding_topic.page,
                ),
            )

        section_entries = [
            entry
            for entry in relevant_entries
            if chapter_entry.page <= entry.page < next_chapter_page + 1
            and entry.level > chapter_level
            and not CHAPTER_TOC_RE.match(entry.title)
            and normalized_header_key(entry.title)
            not in {"QUESTIONS", "ANSWERS", "ANSWERSANDEXPLANATIONS", "ANSWER"}
        ]
        child_entries = [
            entry
            for entry in relevant_entries
            if chapter_entry.page <= entry.page < next_chapter_page + 1
            and entry.level > chapter_level
        ]
        question_start_page = next(
            (
                entry.page
                for entry in child_entries
                if normalized_header_key(entry.title) == "QUESTIONS"
            ),
            chapter_entry.page,
        )
        answer_start_page = next(
            (
                entry.page
                for entry in child_entries
                if normalized_header_key(entry.title)
                in {"ANSWERS", "ANSWERSANDEXPLANATIONS"}
            ),
            None,
        )
        sections: list[SectionSpec] = []
        for section_index, section_entry in enumerate(section_entries, start=1):
            section_number, section_title = format_section_title(
                section_entry.title,
                section_index,
            )
            sections.append(
                SectionSpec(
                    id=f"{book_id}-chapter-{chapter_number}-section-{section_number}-{slugify(section_title)}",
                    title=section_title,
                    number=section_number,
                    page=section_entry.page,
                )
            )

        chapters.append(
            ChapterSpec(
                id=f"{book_id}-chapter-{chapter_number}",
                number=chapter_number,
                title=chapter_title,
                page=question_start_page,
                end_page=next_chapter_page,
                answer_start_page=answer_start_page,
                topic_id=topic_id,
                topic_title=topic_title,
                sections=tuple(sections),
            )
        )

    book_spec = BookSpec(
        id=book_id,
        title=format_book_title(pdf_path),
        source_file_name=pdf_path.name,
        order=order,
        topics=tuple(sorted(topics_by_id.values(), key=lambda topic: topic.order)),
        chapters=tuple(chapters),
    )
    doc.close()
    return book_spec


def active_section(chapter: ChapterSpec, page_number: int) -> SectionSpec | None:
    selected_section: SectionSpec | None = None

    for section in chapter.sections:
        if section.page <= page_number:
            selected_section = section
        else:
            break

    return selected_section


def parse_book(
    book_spec: BookSpec,
    pdf_path: Path,
    image_output_dir: Path,
) -> tuple[list[QuestionDraft], dict[str, str]]:
    doc = fitz.open(pdf_path)
    questions: list[QuestionDraft] = []
    answers: dict[str, str] = {}
    answer_lookup: dict[str, str] = {}
    answer_references: dict[str, list[str]] = {}
    image_map: dict[str, list[str]] = defaultdict(list)
    explanation_image_map: dict[str, list[str]] = defaultdict(list)

    def flush_page_figures(
        page: fitz.Page,
        page_number: int,
        *,
        split_y: float | None,
        mode_end: str | None,
        page_question_anchors: list[tuple[float, str]],
        page_answer_anchors: list[tuple[float, str]],
        stem_carry: str | None,
        answer_carry: str | None,
    ) -> None:
        """Assign every sufficiently large figure on the page to stem or explanation buckets."""
        page_images = page.get_images(full=True)
        page_height = float(page.rect.height)
        y_slack = 8.0

        for image_index, image_info in enumerate(page_images, start=1):
            xref = image_info[0]
            try:
                rects = page.get_image_rects(xref)
            except RuntimeError:
                continue

            for rect_index, rect in enumerate(rects, start=1):
                if (
                    rect.width < _MIN_FIGURE_SIDE_PT
                    or rect.height < _MIN_FIGURE_SIDE_PT
                ):
                    continue
                if rect.width * rect.height < _MIN_FIGURE_AREA_PT2:
                    continue

                if split_y is not None:
                    use_explanation = rect.y0 >= split_y - y_slack
                elif mode_end == "answers":
                    use_explanation = True
                else:
                    use_explanation = False

                if use_explanation:
                    anchors = page_answer_anchors
                    carry = answer_carry
                    destination = explanation_image_map
                else:
                    anchors = page_question_anchors
                    carry = stem_carry
                    destination = image_map

                anchor_idx, owning_question_id = question_image_anchor_index_and_owner(
                    anchors, rect, carry
                )
                if owning_question_id is None:
                    continue
                if (
                    anchor_idx is not None
                    and anchors
                    and not rect_in_question_vertical_band(
                        rect, anchors, anchor_idx, page_height
                    )
                ):
                    continue

                filename = (
                    f"{book_spec.id}_page_{page_number:03d}_img_{image_index}_{rect_index}.png"
                )
                output_path = image_output_dir / filename
                pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), clip=rect, alpha=False)
                pixmap.save(output_path)
                asset_path = f"assets/book_images/{filename}"

                if asset_path not in destination[owning_question_id]:
                    destination[owning_question_id].append(asset_path)

    for chapter in book_spec.chapters:
        current_question: QuestionDraft | None = None
        current_answer: AnswerDraft | None = None
        mode: str | None = None
        current_active_question_id: str | None = None
        question_order = 0
        last_question_number: str | None = None
        chapter_answer_ids: list[str] = []
        answer_queue_index = 0
        answer_region_default_id: str | None = None

        def finalize_question() -> None:
            nonlocal current_question
            if current_question is None:
                return
            current_question.prompt, current_question.choices = parse_question_content(
                current_question.raw_lines
            )
            questions.append(current_question)
            current_question = None

        def finalize_answer() -> None:
            nonlocal current_answer
            if current_answer is None:
                return
            explanation, references = parse_answer_content(current_answer.lines)
            answers[current_answer.question_id] = current_answer.correct_choice
            if explanation:
                answer_lookup[current_answer.question_id] = explanation
            answer_references[current_answer.question_id] = references
            current_answer = None

        for page_number in range(chapter.page, chapter.end_page + 1):
            page = doc[page_number - 1]
            page_lines = extract_page_lines(page)
            page_question_anchors: list[tuple[float, str]] = []
            page_answer_anchors: list[tuple[float, str]] = []
            answers_section_start_y: float | None = None
            current_section = active_section(chapter, page_number)
            page_carry_question_id = current_active_question_id
            line_index = 0

            while line_index < len(page_lines):
                current_line = page_lines[line_index].text
                header_key = normalized_header_key(current_line)

                if header_key == "QUESTIONS":
                    finalize_answer()
                    mode = "questions"
                    answer_region_default_id = None
                    line_index += 1
                    continue

                if header_key == "ANSWERSANDEXPLANATIONS":
                    finalize_question()
                    if answers_section_start_y is None:
                        answers_section_start_y = page_lines[line_index].y
                    mode = "answers"
                    chapter_answer_ids = [
                        q.id for q in questions if q.chapter.id == chapter.id
                    ]
                    answer_queue_index = 0
                    answer_region_default_id = (
                        chapter_answer_ids[0] if chapter_answer_ids else None
                    )
                    line_index += 1
                    continue
                if header_key == "ANSWERS":
                    finalize_question()
                    if answers_section_start_y is None:
                        answers_section_start_y = page_lines[line_index].y
                    mode = "answers"
                    chapter_answer_ids = [
                        q.id for q in questions if q.chapter.id == chapter.id
                    ]
                    answer_queue_index = 0
                    answer_region_default_id = (
                        chapter_answer_ids[0] if chapter_answer_ids else None
                    )
                    line_index += 1
                    continue
                if header_key == "ANSWER":
                    line_index += 1
                    continue

                answer_match = ANSWER_START_RE.match(current_line)
                if answer_match:
                    finalize_question()
                    finalize_answer()
                    answer_question_id = (
                        f"{book_spec.id}-{chapter.number}-{answer_match.group('number').lower()}"
                    )
                    page_answer_anchors.append((page_lines[line_index].y, answer_question_id))
                    current_answer = AnswerDraft(
                        question_id=answer_question_id,
                        correct_choice=answer_match.group("choice").upper(),
                        lines=[],
                    )
                    if (
                        chapter_answer_ids
                        and answer_question_id in chapter_answer_ids
                    ):
                        answer_queue_index = (
                            chapter_answer_ids.index(answer_question_id) + 1
                        )
                    answer_text = clean_text(answer_match.group("text"))
                    if answer_text:
                        current_answer.lines.append(answer_text)
                    line_index += 1
                    continue

                answer_unnumbered_match = ANSWER_UNNUMBERED_RE.match(current_line)
                if (
                    answer_unnumbered_match
                    and mode == "answers"
                    and chapter_answer_ids
                    and answer_queue_index < len(chapter_answer_ids)
                ):
                    finalize_question()
                    finalize_answer()
                    answer_question_id = chapter_answer_ids[answer_queue_index]
                    answer_queue_index += 1
                    page_answer_anchors.append((page_lines[line_index].y, answer_question_id))
                    current_answer = AnswerDraft(
                        question_id=answer_question_id,
                        correct_choice=answer_unnumbered_match.group("choice").upper(),
                        lines=[],
                    )
                    answer_text = clean_text(answer_unnumbered_match.group("text"))
                    if answer_text:
                        current_answer.lines.append(answer_text)
                    line_index += 1
                    continue

                answer_page_ref_match = ANSWER_PAGE_REF_PREFIX_RE.match(current_line)
                if (
                    answer_page_ref_match
                    and mode == "answers"
                    and chapter_answer_ids
                    and answer_queue_index < len(chapter_answer_ids)
                ):
                    finalize_question()
                    finalize_answer()
                    answer_question_id = chapter_answer_ids[answer_queue_index]
                    answer_queue_index += 1
                    page_answer_anchors.append((page_lines[line_index].y, answer_question_id))
                    current_answer = AnswerDraft(
                        question_id=answer_question_id,
                        correct_choice=answer_page_ref_match.group("choice").upper(),
                        lines=[],
                    )
                    answer_text = clean_text(answer_page_ref_match.group("text"))
                    if answer_text:
                        current_answer.lines.append(answer_text)
                    line_index += 1
                    continue

                if (
                    mode == "answers"
                    and current_answer is not None
                    and re.fullmatch(r"\d{1,2}", current_line.strip())
                    and line_index + 1 < len(page_lines)
                ):
                    current_answer.lines.append(page_lines[line_index + 1].text)
                    line_index += 2
                    continue

                if mode == "questions":
                    question_match = QUESTION_START_RE.match(current_line)
                    number_only_match = QUESTION_NUMBER_ONLY_RE.match(current_line)
                    if question_match or number_only_match:
                        question_number = (
                            question_match.group("number")
                            if question_match is not None
                            else number_only_match.group("number")
                        )
                        candidate_number, candidate_suffix = split_question_number(
                            question_number,
                        )
                        if (
                            question_match is None
                            and not candidate_suffix
                            and candidate_number == page_number
                            and (
                                line_index <= 1
                                or line_index >= len(page_lines) - 2
                            )
                        ):
                            line_index += 1
                            continue
                        if current_answer is not None and not is_plausible_next_question(
                            question_number,
                            last_question_number,
                        ):
                            current_answer.lines.append(current_line)
                            line_index += 1
                            continue
                        if current_question is not None and not is_plausible_next_question(
                            question_number,
                            last_question_number,
                        ):
                            current_question.raw_lines.append(current_line)
                            line_index += 1
                            continue
                        finalize_answer()
                        finalize_question()
                        question_order += 1
                        question_id = (
                            f"{book_spec.id}-{chapter.number}-{question_number.lower()}"
                        )
                        current_question = QuestionDraft(
                            id=question_id,
                            book_id=book_spec.id,
                            book_title=book_spec.title,
                            chapter=chapter,
                            question_number=question_number,
                            order=question_order,
                            stem_group=stem_group(question_number),
                            start_page=page_number,
                            topic_id=chapter.topic_id,
                            topic_title=chapter.topic_title,
                            section=current_section,
                        )
                        question_text = clean_text(question_match.group("text")) if question_match else ""
                        if question_text:
                            current_question.raw_lines.append(question_text)
                        page_question_anchors.append((page_lines[line_index].y, question_id))
                        current_active_question_id = question_id
                        last_question_number = question_number
                        line_index += 1
                        continue

                if current_answer is not None:
                    current_answer.lines.append(current_line)
                elif current_question is not None:
                    current_question.raw_lines.append(current_line)

                line_index += 1

            answer_carry_end = (
                current_answer.question_id
                if current_answer is not None
                else (
                    page_answer_anchors[-1][1]
                    if page_answer_anchors
                    else answer_region_default_id
                )
            )
            flush_page_figures(
                page,
                page_number,
                split_y=answers_section_start_y,
                mode_end=mode,
                page_question_anchors=page_question_anchors,
                page_answer_anchors=page_answer_anchors,
                stem_carry=page_carry_question_id,
                answer_carry=answer_carry_end,
            )

        finalize_question()
        finalize_answer()

    doc.close()

    for question in questions:
        question.correct_choice = answers.get(question.id, "")
        question.explanation = answer_lookup.get(question.id, "")
        question.references = answer_references.get(question.id, [])
        question.image_assets = image_map.get(question.id, [])
        question.explanation_image_assets = explanation_image_map.get(
            question.id, []
        )

    promote_stem_only_questions(questions)
    fill_shared_explanations(questions)
    merge_duplicate_questions(questions)
    assign_epub_inline_images(questions, pdf_path, image_output_dir, book_spec.id)
    assign_fallback_page_images(questions, pdf_path, image_output_dir, book_spec.id)

    return questions, answers


def promote_stem_only_questions(questions: list[QuestionDraft]) -> None:
    questions.sort(key=lambda question: (question.chapter.number, question.order))
    rewritten: list[QuestionDraft] = []
    index = 0

    while index < len(questions):
        question = questions[index]
        grouped = [question]
        next_index = index + 1

        while (
            next_index < len(questions)
            and questions[next_index].chapter.id == question.chapter.id
            and questions[next_index].stem_group == question.stem_group
        ):
            grouped.append(questions[next_index])
            next_index += 1

        if (
            question.question_number == question.stem_group
            and not question.choices
            and len(grouped) > 1
        ):
            stem_prompt = question.prompt
            stem_images = list(question.image_assets)
            stem_explanation_images = list(question.explanation_image_assets)
            stem_references = list(question.references)
            stem_explanation = question.explanation

            for child in grouped[1:]:
                child.prompt = clean_text(f"{stem_prompt} {child.prompt}")
                # Only inherit stem figures when this part has no PDF-tagged images,
                # so (b) is not flooded with figures extracted for (a), and vice versa.
                if stem_images and not child.image_assets:
                    child.image_assets = unique_preserving_order(
                        stem_images + child.image_assets
                    )
                if stem_explanation_images and not child.explanation_image_assets:
                    child.explanation_image_assets = unique_preserving_order(
                        stem_explanation_images + child.explanation_image_assets
                    )
                rewritten.append(child)
        else:
            rewritten.extend(grouped)

        index = next_index

    questions.clear()
    questions.extend(rewritten)


def fill_shared_explanations(questions: list[QuestionDraft]) -> None:
    grouped_questions: dict[tuple[str, str, str], list[QuestionDraft]] = defaultdict(list)
    for question in questions:
        grouped_questions[
            (question.book_id, question.chapter.id, question.stem_group)
        ].append(question)

    for grouped in grouped_questions.values():
        shared_explanation = next(
            (question.explanation for question in grouped if question.explanation),
            "",
        )
        shared_references = next(
            (question.references for question in grouped if question.references),
            [],
        )
        shared_explanation_images = next(
            (
                question.explanation_image_assets
                for question in grouped
                if question.explanation_image_assets
            ),
            [],
        )

        if not shared_explanation:
            continue

        for question in grouped:
            if not question.explanation:
                question.explanation = shared_explanation
            if not question.references:
                question.references = list(shared_references)
            if not question.explanation_image_assets and shared_explanation_images:
                question.explanation_image_assets = list(shared_explanation_images)


def merge_duplicate_questions(questions: list[QuestionDraft]) -> None:
    grouped_questions: dict[str, list[QuestionDraft]] = defaultdict(list)
    for question in questions:
        grouped_questions[question.id].append(question)

    merged_questions: list[QuestionDraft] = []

    for grouped in grouped_questions.values():
        grouped.sort(key=lambda question: (question.start_page, question.order))
        base = grouped[0]

        for other in grouped[1:]:
            if len(other.prompt) > len(base.prompt):
                base.prompt = other.prompt

            merged_choices = dict(base.choices)
            for key, value in other.choices.items():
                if key not in merged_choices or len(value) > len(merged_choices[key]):
                    merged_choices[key] = value
            base.choices = merged_choices

            if not base.correct_choice and other.correct_choice:
                base.correct_choice = other.correct_choice

            if len(other.explanation) > len(base.explanation):
                base.explanation = other.explanation

            base.references = unique_preserving_order(
                base.references + other.references
            )
            base.image_assets = unique_preserving_order(
                base.image_assets + other.image_assets
            )
            base.explanation_image_assets = unique_preserving_order(
                base.explanation_image_assets + other.explanation_image_assets
            )

            if base.section is None and other.section is not None:
                base.section = other.section
            if base.topic_id is None and other.topic_id is not None:
                base.topic_id = other.topic_id
            if base.topic_title is None and other.topic_title is not None:
                base.topic_title = other.topic_title

            base.order = min(base.order, other.order)
            base.start_page = min(base.start_page, other.start_page)

        merged_questions.append(base)

    merged_questions.sort(
        key=lambda question: (
            question.book_id,
            question.chapter.number,
            question.order,
            question.id,
        )
    )
    questions.clear()
    questions.extend(merged_questions)


def assign_epub_inline_images(
    questions: list[QuestionDraft],
    source_path: Path,
    image_output_dir: Path,
    book_id: str,
) -> None:
    if source_path.suffix.lower() != ".epub":
        return

    questions_needing_images = [
        question for question in questions if not question.image_assets
    ]
    if not questions_needing_images:
        return

    with zipfile.ZipFile(source_path) as archive:
        text_entries = [
            name
            for name in archive.namelist()
            if name.lower().endswith((".xhtml", ".html", ".htm"))
        ]
        text_content = {
            name: unescape(archive.read(name).decode("utf-8", errors="ignore"))
            for name in text_entries
        }
        exported_assets: dict[str, str] = {}

        for question in questions_needing_images:
            question_markers = build_epub_question_markers(question)
            prompt_patterns = build_epub_prompt_patterns(question.prompt)
            search_patterns = question_markers + prompt_patterns
            if not search_patterns:
                continue

            candidate_entries = prioritize_epub_text_entries(
                text_entries,
                question.chapter.number,
            )
            for entry_name in candidate_entries:
                content = text_content[entry_name]
                image_assets: list[str] = []
                for pattern in search_patterns:
                    match = pattern.search(content)
                    if match is None:
                        continue

                    tail = content[match.end() :]
                    boundary_match = re.search(
                        r'<div class="Q-A">'
                        r'|<p class="num1"'
                        r'|<p class="Questbnum1"'
                        r'|<p class="QUESTION-PARA"',
                        tail,
                        re.IGNORECASE,
                    )
                    search_window = (
                        tail[: boundary_match.start()]
                        if boundary_match is not None
                        else tail[:4000]
                    )
                    image_refs = re.findall(
                        r'<img[^>]+src=["\']([^"\']+)["\']',
                        search_window,
                        re.IGNORECASE,
                    )
                    if not image_refs:
                        continue

                    image_assets = [
                        export_epub_image_asset(
                            archive=archive,
                            entry_name=entry_name,
                            image_ref=image_ref,
                            image_output_dir=image_output_dir,
                            book_id=book_id,
                            question_id=question.id,
                            image_index=image_index,
                            exported_assets=exported_assets,
                        )
                        for image_index, image_ref in enumerate(image_refs, start=1)
                    ]
                    image_assets = [asset for asset in image_assets if asset]
                    if image_assets:
                        break

                if image_assets:
                    question.image_assets = unique_preserving_order(
                        question.image_assets + image_assets
                    )
                    break


def build_epub_question_markers(question: QuestionDraft) -> list[re.Pattern[str]]:
    question_number = re.escape(question.question_number.lower())
    return [
        re.compile(rf'id="q{question_number}"', re.IGNORECASE),
        re.compile(
            rf'<span[^>]*class="colnum"[^>]*>\s*{question_number}\s*</span>',
            re.IGNORECASE,
        ),
        re.compile(rf'>{question_number}</a>\.</b>', re.IGNORECASE),
    ]


def prioritize_epub_text_entries(
    text_entries: list[str],
    chapter_number: int,
) -> list[str]:
    chapter_tokens = {
        f"{chapter_number:02d}.html",
        f"{chapter_number:02d}.xhtml",
        f"ch{chapter_number:03d}.html",
        f"ch{chapter_number:03d}.xhtml",
    }
    prioritized = [
        entry
        for entry in text_entries
        if any(token in entry.lower() for token in chapter_tokens)
    ]
    if prioritized:
        return prioritized
    return text_entries


def build_epub_prompt_patterns(prompt: str) -> list[re.Pattern[str]]:
    words = [
        re.sub(r"^\W+|\W+$", "", word)
        for word in re.split(r"\s+", clean_text(prompt))
    ]
    words = [word for word in words if word]
    if len(words) < 4:
        return []

    candidate_word_groups = [
        words[: min(14, len(words))],
        words[: min(10, len(words))],
        words[: min(8, len(words))],
    ]
    patterns: list[re.Pattern[str]] = []
    seen: set[str] = set()
    for anchor_words in candidate_word_groups:
        pattern = r"\s+".join(re.escape(word) for word in anchor_words)
        if pattern in seen:
            continue
        seen.add(pattern)
        patterns.append(re.compile(pattern, re.IGNORECASE))
    return patterns


def export_epub_image_asset(
    *,
    archive: zipfile.ZipFile,
    entry_name: str,
    image_ref: str,
    image_output_dir: Path,
    book_id: str,
    question_id: str,
    image_index: int,
    exported_assets: dict[str, str],
) -> str:
    if image_ref.startswith("data:"):
        return ""

    archive_path = posixpath.normpath(
        posixpath.join(posixpath.dirname(entry_name), image_ref)
    )
    if archive_path in exported_assets:
        return exported_assets[archive_path]

    try:
        image_bytes = archive.read(archive_path)
    except KeyError:
        return ""

    suffix = Path(archive_path).suffix or ".img"
    filename = f"{book_id}_{question_id}_epub_{image_index}{suffix}"
    output_path = image_output_dir / filename
    output_path.write_bytes(image_bytes)
    asset_path = f"assets/book_images/{filename}"
    exported_assets[archive_path] = asset_path
    return asset_path


def assign_fallback_page_images(
    questions: list[QuestionDraft],
    pdf_path: Path,
    image_output_dir: Path,
    book_id: str,
) -> None:
    doc = fitz.open(pdf_path)
    sorted_questions = sorted(
        questions,
        key=lambda question: (question.chapter.number, question.order),
    )

    for index, question in enumerate(sorted_questions):
        if question.image_assets or not prompt_mentions_figure(question.prompt):
            continue

        candidate_pages = {question.start_page}
        if index + 1 < len(sorted_questions):
            next_question = sorted_questions[index + 1]
            if (
                next_question.chapter.id == question.chapter.id
                and next_question.start_page > question.start_page
            ):
                candidate_pages.update(range(question.start_page, next_question.start_page))
            elif question.start_page < len(doc):
                candidate_pages.add(question.start_page + 1)
        elif question.start_page < len(doc):
            candidate_pages.add(question.start_page + 1)

        for candidate_page in sorted(candidate_pages):
            page = doc[candidate_page - 1]
            filename = f"{book_id}_{question.id}_page_{candidate_page:03d}.png"
            output_path = image_output_dir / filename
            pixmap = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
            pixmap.save(output_path)
            question.image_assets.append(f"assets/book_images/{filename}")

    doc.close()


def build_books_json(
    book_specs: list[BookSpec],
    questions_by_book: dict[str, list[QuestionDraft]],
) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []

    for book_spec in book_specs:
        book_questions = questions_by_book[book_spec.id]
        output.append(
            {
                "id": book_spec.id,
                "title": book_spec.title,
                "sourceFileName": book_spec.source_file_name,
                "order": book_spec.order,
                "topicIds": [topic.id for topic in book_spec.topics],
                "chapterIds": [chapter.id for chapter in book_spec.chapters],
                "questionIds": [question.id for question in book_questions],
            }
        )

    return output


def build_topics_json(
    book_specs: list[BookSpec],
    questions_by_book: dict[str, list[QuestionDraft]],
) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []

    for book_spec in book_specs:
        book_questions = questions_by_book[book_spec.id]
        for topic in book_spec.topics:
            topic_chapters = [
                chapter for chapter in book_spec.chapters if chapter.topic_id == topic.id
            ]
            topic_question_ids = [
                question.id
                for question in book_questions
                if question.topic_id == topic.id
            ]
            output.append(
                {
                    "id": topic.id,
                    "bookId": book_spec.id,
                    "title": topic.title,
                    "order": topic.order,
                    "chapterIds": [chapter.id for chapter in topic_chapters],
                    "questionIds": topic_question_ids,
                }
            )

    return output


def build_chapters_json(
    book_specs: list[BookSpec],
    questions_by_book: dict[str, list[QuestionDraft]],
) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []

    for book_spec in book_specs:
        book_questions = questions_by_book[book_spec.id]
        for chapter in book_spec.chapters:
            chapter_questions = [
                question for question in book_questions if question.chapter.id == chapter.id
            ]
            output.append(
                {
                    "id": chapter.id,
                    "bookId": book_spec.id,
                    "bookTitle": book_spec.title,
                    "topicId": chapter.topic_id,
                    "topicTitle": chapter.topic_title,
                    "number": chapter.number,
                    "title": chapter.title,
                    "questionIds": [question.id for question in chapter_questions],
                    "sections": [
                        {
                            "id": section.id,
                            "chapterId": chapter.id,
                            "number": section.number,
                            "title": section.title,
                            "questionIds": [
                                question.id
                                for question in chapter_questions
                                if question.section is not None
                                and question.section.id == section.id
                            ],
                        }
                        for section in chapter.sections
                    ],
                }
            )

    return output


def build_questions_json(
    book_specs: list[BookSpec],
    questions_by_book: dict[str, list[QuestionDraft]],
) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []
    ordered_questions: list[QuestionDraft] = []

    for book_spec in book_specs:
        ordered_questions.extend(
            sorted(
                questions_by_book[book_spec.id],
                key=lambda question: (question.chapter.number, question.order),
            )
        )

    for sort_order, question in enumerate(ordered_questions, start=1):
        output.append(
            {
                "id": question.id,
                "bookId": question.book_id,
                "bookTitle": question.book_title,
                "topicId": question.topic_id,
                "topicTitle": question.topic_title,
                "chapterId": question.chapter.id,
                "chapterNumber": question.chapter.number,
                "chapterTitle": question.chapter.title,
                "sectionId": question.section.id if question.section is not None else None,
                "sectionTitle": question.section.title if question.section is not None else None,
                "questionNumber": question.question_number,
                "order": question.order,
                "sortOrder": sort_order,
                "prompt": question.prompt,
                "choices": question.choices,
                "correctChoice": question.correct_choice,
                "explanation": question.explanation,
                "references": question.references,
                "imageAssets": question.image_assets,
                "explanationImageAssets": question.explanation_image_assets,
                "stemGroup": question.stem_group,
            }
        )

    return output


def build_validation_report(questions: list[dict[str, object]]) -> dict[str, object]:
    issues: list[dict[str, str]] = []

    for question in questions:
        question_id = str(question["id"])
        choices = question.get("choices", {})
        explanation = str(question.get("explanation", "")).strip()
        correct_choice = str(question.get("correctChoice", "")).strip()
        image_assets = question.get("imageAssets", [])
        explanation_image_assets = question.get("explanationImageAssets", [])
        prompt = str(question.get("prompt", ""))

        if explanation_image_assets is not None and not isinstance(
            explanation_image_assets, list
        ):
            issues.append(
                {
                    "type": "bad_explanation_image_assets",
                    "questionId": question_id,
                    "message": "explanationImageAssets must be a list.",
                }
            )

        if not isinstance(choices, dict) or len(choices) < 2:
            issues.append(
                {
                    "type": "choice_count",
                    "questionId": question_id,
                    "message": "Question does not contain at least 2 answer choices.",
                }
            )

        if not correct_choice:
            issues.append(
                {
                    "type": "missing_answer",
                    "questionId": question_id,
                    "message": "Question is missing a correct answer letter.",
                }
            )

        if not explanation:
            issues.append(
                {
                    "type": "missing_explanation",
                    "questionId": question_id,
                    "message": "Question is missing explanation text.",
                }
            )

        if prompt_mentions_figure(prompt) and not image_assets:
            issues.append(
                {
                    "type": "missing_image",
                    "questionId": question_id,
                    "message": "Prompt suggests an image but no image asset is linked.",
                }
            )

    return {
        "questionCount": len(questions),
        "issueCount": len(issues),
        "issues": issues,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract Core Review PDFs into one Flutter study catalog.",
    )
    parser.add_argument(
        "--inputs",
        type=Path,
        nargs="*",
        default=default_source_paths(),
        help="PDF files or directories containing Core Review PDFs.",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Flutter project root containing the assets directory.",
    )
    args = parser.parse_args()

    pdf_paths = discover_pdf_paths(args.inputs)
    if not pdf_paths:
        raise FileNotFoundError("No source PDFs were found for extraction.")

    project_root = args.project_root.expanduser().resolve()
    data_dir = project_root / "assets" / "data"
    image_dir = project_root / "assets" / "book_images"
    data_dir.mkdir(parents=True, exist_ok=True)
    if image_dir.exists():
        shutil.rmtree(image_dir)
    image_dir.mkdir(parents=True, exist_ok=True)

    book_specs = [
        build_book_spec(pdf_path, order=index + 1)
        for index, pdf_path in enumerate(pdf_paths)
    ]

    questions_by_book: dict[str, list[QuestionDraft]] = {}
    for book_spec, pdf_path in zip(book_specs, pdf_paths):
        questions_by_book[book_spec.id], _ = parse_book(book_spec, pdf_path, image_dir)

    books_json = build_books_json(book_specs, questions_by_book)
    topics_json = build_topics_json(book_specs, questions_by_book)
    chapters_json = build_chapters_json(book_specs, questions_by_book)
    questions_json = build_questions_json(book_specs, questions_by_book)
    validation_report = build_validation_report(questions_json)

    (data_dir / "books.json").write_text(
        json.dumps(books_json, indent=2),
        encoding="utf-8",
    )
    (data_dir / "topics.json").write_text(
        json.dumps(topics_json, indent=2),
        encoding="utf-8",
    )
    (data_dir / "chapters.json").write_text(
        json.dumps(chapters_json, indent=2),
        encoding="utf-8",
    )
    (data_dir / "questions.json").write_text(
        json.dumps(questions_json, indent=2),
        encoding="utf-8",
    )
    (data_dir / "validation_report.json").write_text(
        json.dumps(validation_report, indent=2),
        encoding="utf-8",
    )

    print(f"Extracted {len(books_json)} books")
    print(f"Extracted {len(questions_json)} questions")
    print(f"Saved study catalog to {data_dir}")
    print(f"Saved image assets to {image_dir}")


if __name__ == "__main__":
    main()
