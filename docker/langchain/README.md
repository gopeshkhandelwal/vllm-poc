
Start the langchain service:
```bash
docker compose up -d --build
```

Test the langchain:
```bash
curl -sS http://localhost:9000/selftest
```

Trigger the 2-node workflow using Langchain (Architect → Reviewer)
```bash
curl -sS -X POST http://localhost:9000/run \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Create a short architecture for a FAQ chatbot."}'
```
Trigger Langgraph endpoint
```bash
curl -X POST http://localhost:9000/graph/run \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Design a LangGraph-based AI orchestration service"}'
```

Expected Result Langchain:
```bash
curl -sS -X POST http://localhost:9000/run -H "Content-Type: application/json" -d '{"prompt":"Short FAQ chatbot architecture"}' | jq
{
  "architect": "\nThe chatbot will be developed using the LangChain framework, which is designed",
  "reviewer": " for building context-aware AI applications. The core architecture will consist of the following components"
}
```
Expected Result for LangGraph:
```bash
curl -X POST http://localhost:9000/graph/run   -H "Content-Type: application/json"   -d '{"prompt":"Design a LangGraph-based AI orchestration service"}'
{"architect":" for a smart home system\n\nOkay, so I need to design a LangGraph","reviewer":" application for a smart home system. Let me start by thinking about what a smart"}
```

