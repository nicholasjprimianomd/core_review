"""Populate BookQuestion.examChain for dependent-question sequences.

Some books (notably pediatric-imaging) structure multi-question clinical cases
as separate numbered questions whose prompts reference earlier ones, e.g.
"the patient in Question 14". Those questions should be kept contiguous in a
custom exam pool (see lib/features/exam/exam_pool_builder.dart).

This script scans each question's prompt (and, optionally, explanation) for
references like "Question 14", "Questions 14 and 15", "Question 5a", and
builds undirected chains within each chapter using a union-find. Components of
size >= 2 get a stable examChain id (e.g. "pediatric-imaging-chapter-1-seq-14").

The script only modifies questions whose bookId matches the --book filter (one
or more). Use --dry-run to preview counts, and --no-explanation to scan only
prompts.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Iterable


QUESTION_REF_RE = re.compile(
    r"\bQuestions?\s+(?P<list>\d+[a-z]?(?:\s*(?:,|and|&|through|-)\s*\d+[a-z]?)*)",
    re.IGNORECASE,
)
NUMBER_RE = re.compile(r"(\d+)([a-z]?)", re.IGNORECASE)


class UnionFind:
    def __init__(self) -> None:
        self._parent: dict[str, str] = {}

    def find(self, x: str) -> str:
        self._parent.setdefault(x, x)
        while self._parent[x] != x:
            self._parent[x] = self._parent[self._parent[x]]
            x = self._parent[x]
        return x

    def union(self, a: str, b: str) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self._parent[rb] = ra

    def groups(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = defaultdict(list)
        for node in list(self._parent.keys()):
            out[self.find(node)].append(node)
        return out


def iter_referenced_base_numbers(text: str) -> Iterable[int]:
    """Yield referenced question numbers (leading digits) from a prompt."""
    if not text:
        return
    for match in QUESTION_REF_RE.finditer(text):
        list_text = match.group("list")
        for number_match in NUMBER_RE.finditer(list_text):
            try:
                yield int(number_match.group(1))
            except ValueError:
                continue


def question_base_number(question: dict[str, object]) -> int | None:
    raw = str(question.get("questionNumber", "")).strip()
    match = re.match(r"(\d+)", raw)
    return int(match.group(1)) if match else None


def chain_id_for_component(chapter_id: str, member_ids: list[str], questions_by_id: dict[str, dict[str, object]]) -> str:
    numbers = [
        question_base_number(questions_by_id[qid]) for qid in member_ids
    ]
    anchor = min(n for n in numbers if n is not None)
    return f"{chapter_id}-seq-{anchor}"


def assign_chains(
    questions: list[dict[str, object]],
    books: set[str],
    scan_explanation: bool,
) -> tuple[int, int, list[tuple[str, list[str]]]]:
    questions_by_id = {str(q["id"]): q for q in questions}

    by_chapter: dict[str, list[dict[str, object]]] = defaultdict(list)
    for question in questions:
        if str(question.get("bookId")) not in books:
            continue
        by_chapter[str(question.get("chapterId"))].append(question)

    touched = 0
    chains_created: list[tuple[str, list[str]]] = []
    total_chained = 0

    for chapter_id, chapter_questions in by_chapter.items():
        by_number: dict[int, dict[str, object]] = {}
        for question in chapter_questions:
            base = question_base_number(question)
            if base is not None:
                by_number.setdefault(base, question)

        uf = UnionFind()

        for question in chapter_questions:
            qid = str(question["id"])
            uf.find(qid)

            base_number = question_base_number(question)
            sources: list[str] = [str(question.get("prompt", ""))]
            if scan_explanation:
                sources.append(str(question.get("explanation", "")))

            for text in sources:
                for referenced in iter_referenced_base_numbers(text):
                    if base_number is not None and referenced == base_number:
                        continue
                    referenced_q = by_number.get(referenced)
                    if referenced_q is None:
                        continue
                    uf.union(qid, str(referenced_q["id"]))

        for root, member_ids in uf.groups().items():
            if len(member_ids) < 2:
                continue
            member_ids_sorted = sorted(
                member_ids,
                key=lambda qid: int(questions_by_id[qid].get("sortOrder") or 0),
            )
            chain_id = chain_id_for_component(chapter_id, member_ids_sorted, questions_by_id)
            chains_created.append((chain_id, member_ids_sorted))
            total_chained += len(member_ids_sorted)
            for qid in member_ids_sorted:
                question = questions_by_id[qid]
                if question.get("examChain") != chain_id:
                    question["examChain"] = chain_id
                    touched += 1

    return touched, total_chained, chains_created


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--book",
        action="append",
        default=None,
        help="Book id to process (repeatable). Defaults to pediatric-imaging.",
    )
    parser.add_argument(
        "--scan-explanation",
        action="store_true",
        help=(
            "Also scan explanation text for 'Question N' references. Off by "
            "default because explanations often cross-reference other questions "
            "for context rather than true case dependencies."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report counts without modifying questions.json.",
    )
    parser.add_argument(
        "--print-chains",
        action="store_true",
        help="Print each detected chain (id -> member ids).",
    )
    args = parser.parse_args()

    books = set(args.book or ["pediatric-imaging"])
    questions_path = args.project_root / "assets" / "data" / "questions.json"
    questions = json.loads(questions_path.read_text(encoding="utf-8"))

    touched, total_chained, chains = assign_chains(
        questions,
        books=books,
        scan_explanation=args.scan_explanation,
    )

    print(
        f"Processed books={sorted(books)}; chains={len(chains)}; "
        f"questions_in_chains={total_chained}; updated={touched}"
    )
    if args.print_chains:
        for chain_id, members in sorted(chains):
            numbers = [
                str(next(
                    (q.get("questionNumber") for q in questions if str(q["id"]) == qid),
                    "?",
                ))
                for qid in members
            ]
            print(f"  {chain_id}: [{', '.join(numbers)}] -> {members}")

    if args.dry_run:
        print("(dry run; questions.json not written)")
        return

    original = questions_path.read_bytes()
    eol = "\r\n" if b"\r\n" in original[:4096] else "\n"
    trailing_newline = original.endswith(b"\r\n") or original.endswith(b"\n")
    body = json.dumps(questions, indent=2, ensure_ascii=True)
    if eol != "\n":
        body = body.replace("\n", eol)
    if trailing_newline:
        body += eol
    questions_path.write_bytes(body.encode("utf-8"))
    print(f"Wrote {questions_path}")


if __name__ == "__main__":
    main()
