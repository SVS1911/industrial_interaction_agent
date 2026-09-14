from __future__ import annotations

from google import genai

from app.core.config import settings
from app.schemas.mou_intelligence import MouIntelligenceExtraction
from app.services.prompts.mou_intelligence_prompt import build_prompt


class GeminiMouExtractor:
    def __init__(self, client=None, model: str | None = None):
        if client is not None:
            self.client = client
        else:
            if not settings.gemini_api_key:
                raise RuntimeError("GEMINI_API_KEY is not configured in backend/.env")
            self.client = genai.Client(api_key=settings.gemini_api_key)
        self.model = model or settings.gemini_model

    def extract(
        self,
        *,
        partner_name: str,
        title: str,
        chunks: list[dict],
        db_context: dict,
    ) -> MouIntelligenceExtraction:
        if not chunks:
            raise ValueError("No MoU source chunks were supplied to Gemini")

        prompt = build_prompt(partner_name, title, chunks, db_context)
        interaction = self.client.interactions.create(
            model=self.model,
            input=prompt,
            response_format={
                "type": "text",
                "mime_type": "application/json",
                "schema": MouIntelligenceExtraction.model_json_schema(),
            },
        )
        output_text = getattr(interaction, "output_text", None)
        if not output_text:
            raise RuntimeError("Gemini returned no structured output text")
        return MouIntelligenceExtraction.model_validate_json(output_text)
