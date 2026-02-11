import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { SSEClientTransport } from "@modelcontextprotocol/sdk/client/sse.js";
import { z } from "genkit";
// Configuration for the MCP server
const MCP_SERVER_URL = process.env.MCP_SERVER_URL || "http://localhost:3000/sse";
export async function getMcpClient() {
    const transport = new SSEClientTransport(new URL(MCP_SERVER_URL));
    const client = new Client({
        name: "genkit-client",
        version: "1.0.0",
    }, {
        capabilities: {}
    });
    await client.connect(transport);
    return client;
}
export async function getMcpTools(ai) {
    const client = await getMcpClient();
    const toolsList = await client.listTools();
    const genkitTools = toolsList.tools.map((tool) => {
        // Workaround: Append the JSON schema to the description so the LLM knows what to pass.
        const schemaDescription = `\n\nInput Schema: ${JSON.stringify(tool.inputSchema, null, 2)}`;
        return ai.defineTool({
            name: tool.name,
            description: (tool.description || "") + schemaDescription,
            inputSchema: z.any(),
            outputSchema: z.any(),
        }, async (input) => {
            const result = await client.callTool({
                name: tool.name,
                arguments: input,
            });
            // MCP returns { content: [{ type: 'text', text: '...' }] } usually.
            // Genkit expects a return value (string or object).
            // We should parse the MCP result.
            return result;
        });
    });
    return genkitTools;
}
