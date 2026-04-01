#!/usr/bin/env python3
"""Merge a freshly extracted question row with the prior production row (never downgrade)."""

from __future__ import annotations

import copy
from typing import Any

_IMAGE_MERGE_CAP = 6


def _string_list(paths: Any) -> list[str]:
    if not isinstance(paths, list):
        return []
    return [p for p in paths if isinstance(p, str) and p.strip()]


def _unique_preserving_strs(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for v in values:
        t = v.strip()
        if t in seen:
            continue
        seen.add(t)
        out.append(v)
    return out


def _capped_merge_image_fields(ext: list[str], prior: list[str]) -> list[str]:
    merged = _unique_preserving_strs(ext + prior)
    if len(merged) <= _IMAGE_MERGE_CAP:
        return merged
    ue = _unique_preserving_strs(ext)
    up = _unique_preserving_strs(prior)
    if ue and up:
        chosen = ue if len(ue) <= len(up) else up
    else:
        chosen = ue or up
    return chosen[:_IMAGE_MERGE_CAP]


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

    ext_imgs = _string_list(extracted.get("imageAssets"))
    prior_imgs = _string_list(prior.get("imageAssets"))
    if ext_imgs or prior_imgs:
        merged_imgs = _capped_merge_image_fields(ext_imgs, prior_imgs)
        if merged_imgs:
            out["imageAssets"] = merged_imgs

    ext_exp = _string_list(extracted.get("explanationImageAssets"))
    prior_exp = _string_list(prior.get("explanationImageAssets"))
    if ext_exp or prior_exp:
        merged_exp = _capped_merge_image_fields(ext_exp, prior_exp)
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
