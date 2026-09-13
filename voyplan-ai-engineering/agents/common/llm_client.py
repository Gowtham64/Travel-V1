"""
Unified LLM Provider Client supporting Ollama, OpenAI-compatible APIs,
Google Gemini, and Anthropic.
"""

import os
import json
import urllib.request
import urllib.error
from typing import Dict, Any, Optional

class LLMClient:
    ROLE_MAPPING = {
        "ceo": {
            "primary_provider": "gemini",
            "primary_model": "gemini-flash-lite-latest",
            "description": "Gemini 1.5 Pro / Flash via Google AI Studio (Free Tier)"
        },
        "rnd": {
            "primary_provider": "gemini",
            "primary_model": "gemini-flash-lite-latest",
            "description": "Gemini 1.5 Flash via Google AI Studio (Free Tier)"
        },
        "coding": {
            "groq_model": "qwen/qwen3.6-27b",
            "openrouter_model": "qwen/qwen-2.5-coder-32b-instruct:free",
            "ollama_model": "qwen2.5-coder:32b",
            "gemini_model": "gemini-flash-lite-latest",
            "description": "Qwen 2.5 Coder 32B / DeepSeek-V3 via Groq Free API / OpenRouter"
        },
        "testing": {
            "groq_model": "openai/gpt-oss-120b",
            "ollama_model": "deepseek-r1:14b",
            "gemini_model": "gemini-flash-lite-latest",
            "description": "DeepSeek-R1 (Distill 70B/14B) via Groq / Ollama"
        },
        "security": {
            "groq_model": "openai/gpt-oss-120b",
            "gemini_model": "gemini-flash-lite-latest",
            "description": "Llama 3.3 70B via Groq Cloud Free Tier"
        },
        "deployment": {
            "ollama_model": "llama3.1:8b",
            "groq_model": "openai/gpt-oss-20b",
            "gemini_model": "gemini-flash-lite-latest",
            "description": "Llama 3.1 8B via Ollama / Groq Free Tier"
        }
    }

    def __init__(self, provider: Optional[str] = None, model: Optional[str] = None, role: Optional[str] = None):
        self._load_env_fallback()
        self.role = (role or "").lower()
        self.ollama_base_url = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

        # Resolve provider and model based on role if specified
        resolved_provider = provider
        resolved_model = model

        if self.role in self.ROLE_MAPPING:
            cfg = self.ROLE_MAPPING[self.role]
            if self.role in ["ceo", "rnd"]:
                resolved_provider = "gemini"
                resolved_model = cfg["primary_model"]
            elif self.role == "coding":
                if os.environ.get("GROQ_API_KEY"):
                    resolved_provider = "groq"
                    resolved_model = cfg["groq_model"]
                elif os.environ.get("OPENROUTER_API_KEY"):
                    resolved_provider = "openrouter"
                    resolved_model = cfg["openrouter_model"]
                else:
                    resolved_provider = "gemini"
                    resolved_model = cfg["gemini_model"]
            elif self.role == "testing":
                if os.environ.get("GROQ_API_KEY"):
                    resolved_provider = "groq"
                    resolved_model = cfg["groq_model"]
                else:
                    resolved_provider = "gemini"
                    resolved_model = cfg["gemini_model"]
            elif self.role == "security":
                if os.environ.get("GROQ_API_KEY"):
                    resolved_provider = "groq"
                    resolved_model = cfg["groq_model"]
                else:
                    resolved_provider = "gemini"
                    resolved_model = cfg["gemini_model"]
            elif self.role == "deployment":
                if os.environ.get("GROQ_API_KEY"):
                    resolved_provider = "groq"
                    resolved_model = cfg["groq_model"]
                else:
                    resolved_provider = "gemini"
                    resolved_model = cfg["gemini_model"]

        self.provider = (
            resolved_provider 
            or os.environ.get("MODEL_PROVIDER") 
            or ("gemini" if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
                else "groq" if os.environ.get("GROQ_API_KEY")
                else "openrouter" if os.environ.get("OPENROUTER_API_KEY")
                else "openai" if os.environ.get("OPENAI_API_KEY")
                else "anthropic" if os.environ.get("ANTHROPIC_API_KEY")
                else "ollama")
        ).lower()
        
        self.model = resolved_model or os.environ.get("MODEL_NAME") or self._default_model(self.provider)

    @staticmethod
    def _load_env_fallback():
        """Searches parent directories for .env files and loads missing keys."""
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        paths = [
            os.path.join(base, ".env"),
            os.path.join(base, "..", "backend", ".env"),
            os.path.join(base, "..", ".env"),
        ]
        for p in paths:
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        for line in f:
                            line = line.strip()
                            if line and not line.startswith("#") and "=" in line:
                                k, v = line.split("=", 1)
                                k = k.strip()
                                v = v.strip().strip("'\"")
                                if k not in os.environ and v:
                                    os.environ[k] = v
                except Exception:
                    pass

    def _default_model(self, provider: str) -> str:
        defaults = {
            "ollama": "qwen2.5-coder:latest",
            "openai": "gpt-4o",
            "gemini": "gemini-flash-lite-latest",
            "groq": "llama-3.3-70b-versatile",
            "openrouter": "meta-llama/llama-3.3-70b-instruct:free",
            "anthropic": "claude-3-5-sonnet-20241022",
        }
        return defaults.get(provider, "gemini-flash-lite-latest")

    def query(self, system_prompt: str, user_prompt: str, expect_json: bool = True) -> Dict[str, Any]:
        """Dispatches query to the configured provider, falling back if offline."""
        try:
            if self.provider == "ollama":
                return self._call_ollama(system_prompt, user_prompt, expect_json)
            elif self.provider == "gemini":
                return self._call_gemini(system_prompt, user_prompt, expect_json)
            elif self.provider in ["openai", "groq", "openrouter"]:
                return self._call_openai_compat(system_prompt, user_prompt, expect_json)
            elif self.provider == "anthropic":
                return self._call_anthropic(system_prompt, user_prompt, expect_json)
            else:
                return self._call_ollama(system_prompt, user_prompt, expect_json)
        except Exception as e:
            # If network or local daemon is unreachable, log warning and return structured fallback
            return {
                "error": str(e),
                "fallback_mode": True,
                "provider": self.provider,
                "model": self.model
            }

    def _call_ollama(self, system: str, prompt: str, expect_json: bool) -> Dict[str, Any]:
        url = f"{self.ollama_base_url}/api/chat"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt}
            ],
            "stream": False,
            "options": {"temperature": 0.2}
        }
        if expect_json:
            payload["format"] = "json"
        
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            content = res_json.get("message", {}).get("content", "")
            return json.loads(content) if expect_json else {"text": content}

    def _call_gemini(self, system: str, prompt: str, expect_json: bool) -> Dict[str, Any]:
        key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
        if not key:
            raise ValueError("GEMINI_API_KEY or GOOGLE_API_KEY is not configured")

        # Models ordered by availability and latency
        candidate_models = [self.model, "gemini-flash-lite-latest", "gemini-2.5-flash-lite", "gemini-flash-latest"]
        # Deduplicate while preserving order
        seen = set()
        models_to_try = []
        for m in candidate_models:
            clean = "gemini-flash-lite-latest" if ("1.5" in m or "2.5-flash" == m) else m
            if clean not in seen:
                seen.add(clean)
                models_to_try.append(clean)

        last_error = None
        for model_name in models_to_try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
            body: Dict[str, Any] = {
                "systemInstruction": {"parts": [{"text": system}]},
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.2}
            }
            if expect_json:
                body["generationConfig"]["responseMimeType"] = "application/json"

            data = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=45) as resp:
                    res_json = json.loads(resp.read().decode("utf-8"))
                    text = res_json["candidates"][0]["content"]["parts"][0]["text"]
                    return json.loads(text) if expect_json else {"text": text}
            except urllib.error.HTTPError as e:
                last_error = e
                # If 503 or 404, try next candidate model
                if e.code in [503, 404, 429]:
                    continue
                else:
                    raise
            except Exception as e:
                last_error = e
                continue

        if last_error:
            raise last_error
        raise RuntimeError("All candidate Gemini models failed to generate response")

    def _call_openai_compat(self, system: str, prompt: str, expect_json: bool) -> Dict[str, Any]:
        if self.provider == "groq":
            key = os.environ.get("GROQ_API_KEY")
            url = "https://api.groq.com/openai/v1/chat/completions"
        elif self.provider == "openrouter":
            key = os.environ.get("OPENROUTER_API_KEY")
            url = "https://openrouter.ai/api/v1/chat/completions"
        else:
            key = os.environ.get("OPENAI_API_KEY")
            url = "https://api.openai.com/v1/chat/completions"

        if not key:
            raise ValueError(f"API key for {self.provider} is not configured")
            
        body: Dict[str, Any] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.2
        }
        if self.provider == "groq":
            body["max_tokens"] = 800

        data = json.dumps(body).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}",
            "User-Agent": "VoyPlan-AI-Agent/1.0"
        }
        if self.provider == "openrouter":
            headers["HTTP-Referer"] = "https://voyplan.in"
            headers["X-Title"] = "VoyPlan AI Engineering"

        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=60) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            content = res_json["choices"][0]["message"]["content"]
            if expect_json:
                clean = content.strip()
                # Strip thinking tags if returned by reasoning models
                if "<think>" in clean and "</think>" in clean:
                    clean = clean.split("</think>", 1)[-1].strip()
                if clean.startswith("```json"):
                    clean = clean[7:]
                if clean.startswith("```"):
                    clean = clean[3:]
                if clean.endswith("```"):
                    clean = clean[:-3]
                clean = clean.strip()
                return json.loads(clean)
            return {"text": content}

    def _call_anthropic(self, system: str, prompt: str, expect_json: bool) -> Dict[str, Any]:
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise ValueError("ANTHROPIC_API_KEY is not configured")
            
        url = "https://api.anthropic.com/v1/messages"
        body = {
            "model": self.model,
            "max_tokens": 4096,
            "system": system,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2
        }
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={
            "Content-Type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01"
        })
        with urllib.request.urlopen(req, timeout=60) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            content = res_json["content"][0]["text"]
            return json.loads(content) if expect_json else {"text": content}
