Start the langgraph service from root:
```bash
docker compose up -d --build
```

Trigger Langgraph endpoint
```bash
curl -X POST http://localhost:9000/graph/run \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Design a LangGraph-based AI orchestration service"}'
```

Expected Result for LangGraph:
```bash
curl -X POST http://localhost:9000/graph/run   -H "Content-Type: application/json"   -d '{"prompt":"Design a LangGraph-based AI orchestration service"}'
{"architect":" for a smart home system\n\nOkay, so I need to design a LangGraph","reviewer":" application for a smart home system. Let me start by thinking about what a smart"}
```