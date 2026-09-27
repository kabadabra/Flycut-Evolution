## graphify

Generate the local code graph with `graphify update . --no-cluster`. The `graphify-out/` directory is ignored by Git.

When the user asks for Graphify, use the installed Graphify skill and regenerate the graph if it is missing.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Generated graph files are local artifacts and are not part of a pull request.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update . --no-cluster` to keep the graph current without an LLM.
