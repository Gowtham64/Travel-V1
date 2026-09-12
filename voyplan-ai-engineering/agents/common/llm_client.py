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
    def __init__(self, provider: Optional[str] = None, model: Optional[str] = None):
        self.provider = (
            provider 
            or os.environ.get("MODEL_PROVIDER") 
            or ("gemini" if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
                else "openai" if os.environ.get("OPENAI_API_KEY")
                else "anthropic" if os.environ.get("ANTHROPIC_API_KEY")
                else "ollama")
        ).lower()
        
        self.model = model or os.environ.get("MODEL_NAME") or self._default_model(self.provider)
        self.ollama_base_url = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

    def _default_model(self, provider: str) -> str:
        defaults = {
            "ollama": "qwen2.5-coder:latest",
            "openai": "gpt-4o",
            "gemini": "gemini-1.5-flash",
            "anthropic": "claude-3-5-sonnet-20241022",
        }
        return defaults.get(provider, "qwen2.5-coder:latest")

    def query(self, system_prompt: str, user_prompt: str, expect_json: bool = True) -> Dict[str, Any]:
        """Dispatches query to the configured provider, falling back if offline."""
        try:
            if self.provider == "ollama":
                return self._call_ollama(system_prompt, user_prompt, expect_json)
            elif self.provider == "gemini":
                return self._call_gemini(system_prompt, user_prompt, expect_json)
            elif self.provider == "openai":
                return self._call_openai(system_prompt, user_prompt, expect_json)
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
        
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={key}"
        body: Dict[str, Any] = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.2}
        }
        if expect_json:
            body["generationConfig"]["responseMimeType"] = "application/json"
            
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            text = res_json["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(text) if expect_json else {"text": text}

    def _call_openai(self, system: str, prompt: str, expect_json: bool) -> Dict[str, Any]:
        key = os.environ.get("OPENAI_API_KEY")
        if not key:
            raise ValueError("OPENAI_API_KEY is not configured")
            
        url = "https://api.openai.com/v1/chat/completions"
        body = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.2
        }
        if expect_json:
            body["response_format"] = {"type": "json_object"}
            
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}"
        })
        with urllib.request.urlopen(req, timeout=60) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            content = res_json["choices"][0]["message"]["content"]
            return json.loads(content) if expect_json else {"text": content}

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
