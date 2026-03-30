#!/usr/bin/env python3
"""Merge a freshly extracted question row with the prior production row (never downgrade)."""

from __future__ import annotations

import copy
from typing import Any


def _choice_count(choices: Any) -> int:
    if not isinstance(choices, dict):
        return 0
    return len(choices)


def merge_extracted_question(
    prior: dict[str, Any] | None, extracted: dict[str, Any]
) -> dict[str, Any]:
    """Return a row that prefers the new extract for structure, but keeps prior data when the extract is weaker."""
    if not prior:
        return copy.deepcopy(extracted)

    out = copy.deepcopy(extracted)
    prior_ch = prior.get("choices") or {}
    ext_ch = extracted.get("choices") or {}
    if not isinstance(prior_ch, dict):
        prior_ch = {}
    if not isinstance(ext_ch, dict):
        ext_ch = {}

    prior_n = _choice_count(prior_ch)
    ext_n = _choice_count(ext_ch)

    # Restore dropped answers / explanations
    for field in ("correctChoice", "explanation"):
        ext_val = str(extracted.get(field, "") or "").strip()
        prior_val = str(prior.get(field, "") or "").strip()
        if not ext_val and prior_val:
            out[field] = prior[field]

    if not extracted.get("references") and prior.get("references"):
        out["references"] = list(prior["references"])

    if not str(extracted.get("prompt", "") or "").strip() and str(
        prior.get("prompt", "") or ""
    ).strip():
        out["prompt"] = prior["prompt"]

    letter = str(out.get("correctChoice", "") or "").strip()

    # Choices: never replace a full option set with an empty one
    if ext_n < 2 <= prior_n:
        out["choices"] = copy.deepcopy(prior_ch)
    elif prior_n < 2 <= ext_n:
        out["choices"] = copy.deepcopy(ext_ch)
    elif ext_n >= 2 and prior_n >= 2:
        if letter and letter in ext_ch:
            out["choices"] = copy.deepcopy(ext_ch)
        elif letter and letter in prior_ch:
            out["choices"] = copy.deepcopy(prior_ch)
        else:
            # Ambiguous binding: keep the set that still contains the chosen letter, else prior
            if letter in prior_ch:
                out["choices"] = copy.deepcopy(prior_ch)
            elif letter in ext_ch:
                out["choices"] = copy.deepcopy(ext_ch)
            else:
                out["choices"] = copy.deepcopy(prior_ch)
    else:
        out["choices"] = copy.deepcopy(ext_ch if ext_n else prior_ch)

    # Image paths: preserve union order (extract first, then prior-only)
    ext_imgs = extracted.get("imageAssets") or []
    prior_imgs = prior.get("imageAssets") or []
    if isinstance(ext_imgs, list) or isinstance(prior_imgs, list):
        merged_imgs: list[str] = []
        seen: set[str] = set()
        for src in (list(ext_imgs) + list(prior_imgs)):
            if isinstance(src, str) and src.strip() and src not in seen:
                seen.add(src)
                merged_imgs.append(src)
        if merged_imgs:
            out["imageAssets"] = merged_imgs

    ext_exp = extracted.get("explanationImageAssets") or []
    prior_exp = prior.get("explanationImageAssets") or []
    if isinstance(ext_exp, list) or isinstance(prior_exp, list):
        merged_exp: list[str] = []
        seen_exp: set[str] = set()
        for src in (list(ext_exp) + list(prior_exp)):
            if isinstance(src, str) and src.strip() and src not in seen_exp:
                seen_exp.add(src)
                merged_exp.append(src)
        if merged_exp:
            out["explanationImageAssets"] = merged_exp

    if prior.get("validationRelaxed") is True:
        out["validationRelaxed"] = True

    return out


def merge_book_extract(
    prior_rows: list[dict[str, Any]], extracted_rows: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    prior_by_id = {q["id"]: q for q in prior_rows}
    return [merge_extracted_question(prior_by_id.get(q["id"]), q) for q in extracted_rows]
