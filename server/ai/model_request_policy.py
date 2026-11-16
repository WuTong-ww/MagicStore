"""Model transport policy matching the Godot direct-HTTP providers.

Reasoning is private computation, never a substitute for visible JSON content.
Stage validators remain responsible for facts, effects and independent review.
"""
from __future__ import annotations

import json


def family(model):
    name = model.strip().casefold().replace("\\", "/").rsplit("/", 1)[-1]
    if name.startswith("deepseek"):
        return "deepseek"
    if name.startswith("glm-5.3"):
        return "glm"
    if name.startswith("qwen3"):
        return "qwen"
    return "generic"


def build_body(model, system, context, stage="general"):
    person = stage in ("person_generate", "person_review")
    normalized_stage = stage.removeprefix("person_") if person else stage
    generating = normalized_stage == "generate"
    # General is the legacy A profile/event path, which has no Godot dialogue
    # counterpart. Keep its previous generic sampling settings.
    body = {
        "model": model,
        "stream": False,
        "temperature": (0.4 if person else 0.55) if generating else (0.2 if stage == "general" else 0),
        "max_tokens": 2304 if person and generating else (1000 if stage == "general" else 1024),
        "response_format": {"type": "json_object"},
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": json.dumps(context, ensure_ascii=False)}],
    }
    model_family = family(model)
    if model_family == "deepseek":
        body["thinking"] = {"type": "disabled"}
        if stage == "general":
            body["max_tokens"] = 1024
        if generating and not person:
            body["temperature"] = 0.25
    elif model_family == "glm":
        body["thinking"] = {"type": "enabled"}
        body["reasoning_effort"] = "low"
        body["max_tokens"] = 6144 if person and generating else 4096
        if generating and not person:
            body["temperature"] = 0.25
    elif model_family == "qwen":
        body["enable_thinking"] = False
        body["chat_template_kwargs"] = {"enable_thinking": False}
    return body


def chat_object(value):
    if not isinstance(value, dict) or not isinstance(value.get("choices"), list) or not value["choices"]:
        raise ValueError("missing model choices")
    choice = value["choices"][0]
    if not isinstance(choice, dict) or ("finish_reason" in choice and choice["finish_reason"] != "stop"):
        raise ValueError("model response did not finish")
    message = choice.get("message")
    if not isinstance(message, dict) or not isinstance(message.get("content"), str):
        raise ValueError("missing model content")
    content = message["content"].strip()
    if content.startswith("```"):
        line_end = content.find("\n")
        if line_end < 0 or content[:line_end].strip().casefold() not in ("```", "```json") or not content.endswith("```"):
            raise ValueError("invalid JSON content fence")
        content = content[line_end + 1:-3].strip()
    result = json.loads(content)
    if not isinstance(result, dict):
        raise ValueError("model content is not an object")
    return result
