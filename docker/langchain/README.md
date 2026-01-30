
Start the langchain service:
```bash
docker compose up -d --build
```

Test the langchain:
```bash
curl -sS http://localhost:9000/selftest
```

Trigger the 2-node workflow (Architect → Reviewer)
```bash
curl -sS -X POST http://localhost:9000/run \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Create a short architecture for a FAQ chatbot."}'
```

Expected Result:
```bash
curl -sS -X POST http://localhost:9000/run -H "Content-Type: application/json" -d '{"prompt":"Short FAQ chatbot architecture"}' | jq
{
  "architect": "\nThe chatbot will be developed using the LangChain framework, which is designed",
  "reviewer": " for building context-aware AI applications. The core architecture will consist of the following components"
}
```
